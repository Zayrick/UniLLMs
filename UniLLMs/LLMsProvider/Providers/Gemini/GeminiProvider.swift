//
//  GeminiProvider.swift
//  UniLLMs
//
//  Native Google Gemini provider adapter.
//  Created by Codex on 2026/5/22.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let gemini = LLMsProviderKind(rawValue: "gemini")
}

struct GeminiProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "Gemini"
        static let defaultAPIBase = "https://generativelanguage.googleapis.com/v1beta"
    }

    enum ConfigurationKey {
        static let apiKey = "apiKey"
        static let apiBase = "apiBase"
    }

    let apiClient: GeminiAPIClient

    init(
        apiClient: GeminiAPIClient = GeminiAPIClient(
            serviceName: Metadata.displayName,
            defaultAPIBase: Metadata.defaultAPIBase
        )
    ) {
        self.apiClient = apiClient
    }

    var kind: LLMsProviderKind {
        .gemini
    }

    var displayName: String {
        Metadata.displayName
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.modelList, .streamingChat, .tools]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration(
            values: [
                ConfigurationKey.apiKey: "",
                ConfigurationKey.apiBase: Metadata.defaultAPIBase
            ]
        )
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        [
            LLMsProviderConfigurationField(
                id: "name",
                title: String(localized: .providerFieldName),
                placeholder: displayName,
                binding: .providerName,
                inputKind: .plain
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.apiKey,
                title: String(localized: .providerFieldKey),
                placeholder: String(localized: .providerFieldApiKeyPlaceholderFormat(displayName)),
                binding: .configurationValue(ConfigurationKey.apiKey),
                inputKind: .secret,
                isRequired: true
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.apiBase,
                title: String(localized: .providerFieldApiBase),
                placeholder: Metadata.defaultAPIBase,
                binding: .configurationValue(ConfigurationKey.apiBase),
                inputKind: .url,
                isRequired: true
            )
        ]
    }

    var modelSource: LLMsProviderModelSource {
        .remote
    }

    func configurationSummary(for configuration: LLMsProviderConfiguration) -> String? {
        configuration[ConfigurationKey.apiBase]
    }

    func fetchModels(configuration: LLMsProviderConfiguration) async throws -> [LLMsProviderModel] {
        try await apiClient.fetchModels(
            apiBase: configuration[ConfigurationKey.apiBase],
            apiKey: configuration[ConfigurationKey.apiKey]
        )
    }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {
        guard !configuration[ConfigurationKey.apiKey].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiProviderError.missingAPIKey(displayName)
        }
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        do {
            guard !Self.containsFileAttachments(request) else {
                throw GeminiProviderError.unsupportedFileAttachments(displayName)
            }

            let renderedPrompt = try GeminiChatPromptRenderer.render(request: request)
            let stream = apiClient.streamGenerateContent(
                apiBase: configuration[ConfigurationKey.apiBase],
                apiKey: configuration[ConfigurationKey.apiKey],
                model: request.modelID,
                systemInstruction: renderedPrompt.systemInstruction,
                contents: renderedPrompt.contents,
                tools: request.context.availableTools.isEmpty
                    ? nil
                    : [GeminiTool(functionDeclarations: request.context.availableTools.map(GeminiFunctionDeclaration.init(definition:)))]
            )

            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await delta in stream {
                            continuation.yield(
                                ChatResponseDelta(
                                    content: delta.content,
                                    toolCalls: delta.toolCalls
                                )
                            )
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    private static func containsFileAttachments(_ request: ChatRequest) -> Bool {
        request.messages.contains { message in
            message.attachments.contains { $0.kind == .file }
        }
    }
}

enum GeminiProviderError: LocalizedError, Equatable {
    static let thoughtSignatureMetadataKey = "gemini.thoughtSignature"

    case missingAPIKey(String)
    case unsupportedFileAttachments(String)
    case missingAttachmentData(String)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(displayName):
            return String(localized: .providersErrorMissingApiKeyFormat(displayName))
        case let .unsupportedFileAttachments(displayName):
            return String(localized: .providersErrorUnsupportedFileAttachmentsFormat(displayName))
        case let .missingAttachmentData(filename):
            return String(localized: .providersErrorMissingAttachmentDataFormat(filename))
        }
    }
}

nonisolated struct GeminiRenderedPrompt: Equatable {
    var systemInstruction: GeminiContent?
    var contents: [GeminiContent]
}

nonisolated enum GeminiChatPromptRenderer {
    static func render(request: ChatRequest) throws -> GeminiRenderedPrompt {
        let prompt = ChatPromptAssembler().assemblePrompt(from: request)
        var contents: [GeminiContent] = []
        var toolNamesByID: [String: String] = [:]
        var pendingToolResponses: [GeminiPart] = []

        func flushToolResponses() {
            guard !pendingToolResponses.isEmpty else {
                return
            }

            contents.append(GeminiContent(role: "user", parts: pendingToolResponses))
            pendingToolResponses = []
        }

        for message in prompt.messages {
            if message.role == .tool {
                let toolName = message.toolCallID.flatMap { toolNamesByID[$0] }
                    ?? message.toolDisplayName
                    ?? "tool_result"
                pendingToolResponses.append(
                    .functionResponse(
                        id: message.toolCallID,
                        name: toolName,
                        response: functionResponsePayload(for: message)
                    )
                )
                continue
            }

            flushToolResponses()

            switch message.role {
            case .user:
                contents.append(
                    GeminiContent(
                        role: "user",
                        parts: try userParts(for: message)
                    )
                )
            case .assistant:
                var parts: [GeminiPart] = []
                if !message.content.isEmpty {
                    parts.append(.text(message.content))
                }
                for toolCall in message.toolCalls ?? [] {
                    toolNamesByID[toolCall.id] = toolCall.toolID
                    parts.append(
                        .functionCall(
                            id: toolCall.id,
                            name: toolCall.toolID,
                            args: toolCall.arguments,
                            thoughtSignature: toolCall.providerMetadata[GeminiProviderError.thoughtSignatureMetadataKey]?.stringValue
                        )
                    )
                }
                contents.append(GeminiContent(role: "model", parts: parts.isEmpty ? [.text("")] : parts))
            case .tool:
                break
            case .system:
                contents.append(GeminiContent(role: "user", parts: [.text(message.content)]))
            }
        }

        flushToolResponses()
        let systemInstruction = prompt.instructionText.map {
            GeminiContent(parts: [.text($0)])
        }
        return GeminiRenderedPrompt(systemInstruction: systemInstruction, contents: contents)
    }

    private static func userParts(for message: ChatMessage) throws -> [GeminiPart] {
        var parts: [GeminiPart] = []
        if !message.content.isEmpty {
            parts.append(.text(message.content))
        }

        for attachment in message.attachments {
            guard let data = try? ChatAttachmentStore.shared.loadData(for: attachment),
                  !data.isEmpty else {
                throw GeminiProviderError.missingAttachmentData(attachment.filename)
            }

            switch attachment.kind {
            case .image:
                parts.append(
                    .inlineData(
                        mimeType: attachment.contentType.isEmpty
                            ? "application/octet-stream"
                            : attachment.contentType,
                        data: data.base64EncodedString()
                    )
                )
            case .file:
                throw GeminiProviderError.unsupportedFileAttachments("Gemini")
            }
        }

        return parts.isEmpty ? [.text("")] : parts
    }

    private static func functionResponsePayload(for message: ChatMessage) -> JSONValue {
        if message.toolStatus == .error {
            return .object([
                "error": .string(message.content)
            ])
        }

        return .object([
            "result": .string(message.content)
        ])
    }
}

nonisolated struct GeminiContent: Codable, Equatable {
    var role: String? = nil
    var parts: [GeminiPart]
}

nonisolated enum GeminiPart: Codable, Equatable {
    case text(String)
    case inlineData(mimeType: String, data: String)
    case functionCall(id: String?, name: String, args: JSONValue, thoughtSignature: String?)
    case functionResponse(id: String?, name: String, response: JSONValue)

    nonisolated private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
        case functionCall
        case functionResponse
        case thoughtSignature
    }

    nonisolated private struct Blob: Codable, Equatable {
        var mimeType: String
        var data: String
    }

    nonisolated private struct FunctionCall: Codable, Equatable {
        var id: String?
        var name: String
        var args: JSONValue?
    }

    nonisolated private struct FunctionResponse: Codable, Equatable {
        var id: String?
        var name: String
        var response: JSONValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(text)
        } else if let functionCall = try container.decodeIfPresent(FunctionCall.self, forKey: .functionCall) {
            self = .functionCall(
                id: functionCall.id,
                name: functionCall.name,
                args: functionCall.args ?? .object([:]),
                thoughtSignature: try container.decodeIfPresent(String.self, forKey: .thoughtSignature)
            )
        } else if let functionResponse = try container.decodeIfPresent(FunctionResponse.self, forKey: .functionResponse) {
            self = .functionResponse(
                id: functionResponse.id,
                name: functionResponse.name,
                response: functionResponse.response
            )
        } else if let inlineData = try container.decodeIfPresent(Blob.self, forKey: .inlineData) {
            self = .inlineData(mimeType: inlineData.mimeType, data: inlineData.data)
        } else {
            self = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(text, forKey: .text)
        case let .inlineData(mimeType, data):
            try container.encode(Blob(mimeType: mimeType, data: data), forKey: .inlineData)
        case let .functionCall(id, name, args, thoughtSignature):
            try container.encode(FunctionCall(id: id, name: name, args: args), forKey: .functionCall)
            try container.encodeIfPresent(thoughtSignature, forKey: .thoughtSignature)
        case let .functionResponse(id, name, response):
            try container.encode(
                FunctionResponse(id: id, name: name, response: response),
                forKey: .functionResponse
            )
        }
    }
}

nonisolated struct GeminiTool: Encodable, Equatable {
    var functionDeclarations: [GeminiFunctionDeclaration]
}

nonisolated struct GeminiFunctionDeclaration: Encodable, Equatable {
    var name: String
    var description: String
    var parameters: JSONValue

    init(definition: ToolDefinition) {
        name = definition.name
        description = definition.summary
        parameters = definition.parameters
    }
}

nonisolated struct GeminiStreamDelta: Equatable {
    var content: String = ""
    var toolCalls: [ChatToolCall] = []
}

nonisolated struct GeminiAPIClient {
    nonisolated enum APIError: LocalizedError, Equatable {
        case invalidAPIBase(String)
        case invalidResponse(String)
        case serverStatus(String, Int, String?)
        case streamError(String)

        var errorDescription: String? {
            switch self {
            case let .invalidAPIBase(apiBase):
                return String(localized: .providersErrorInvalidApiBaseFormat(apiBase))
            case let .invalidResponse(serviceName):
                return String(localized: .providersErrorInvalidResponseFormat(serviceName))
            case let .serverStatus(serviceName, statusCode, message):
                if let message, !message.isEmpty {
                    return String(localized: .providersErrorHttpStatusMessageFormat(serviceName, statusCode, message))
                }
                return String(localized: .providersErrorHttpStatusFormat(serviceName, statusCode))
            case let .streamError(message):
                return message
            }
        }
    }

    nonisolated private struct ModelsResponse: Decodable {
        var models: [Model]
    }

    nonisolated private struct Model: Decodable {
        var name: String
        var displayName: String?
        var inputTokenLimit: Int?
        var supportedGenerationMethods: [String]?
    }

    nonisolated private struct GenerateContentRequest: Encodable {
        var contents: [GeminiContent]
        var tools: [GeminiTool]?
        var systemInstruction: GeminiContent?
    }

    nonisolated private struct GenerateContentResponse: Decodable {
        var candidates: [Candidate]?
        var promptFeedback: PromptFeedback?
        var error: ResponseError?

        nonisolated struct Candidate: Decodable {
            var content: GeminiContent?
            var finishReason: String?
            var finishMessage: String?
        }

        nonisolated struct PromptFeedback: Decodable {
            var blockReason: String?
            var blockReasonMessage: String?
        }

        nonisolated struct ResponseError: Decodable {
            var message: String?
        }
    }

    var session: URLSession = .shared
    var serviceName: String
    var defaultAPIBase: String

    func fetchModels(apiBase: String, apiKey: String) async throws -> [LLMsProviderModel] {
        var request = URLRequest(url: try modelsURL(apiBase: apiBase))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(serviceName)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverStatus(serviceName, httpResponse.statusCode, String(data: data, encoding: .utf8))
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.models
            .filter { $0.supportedGenerationMethods?.contains("generateContent") != false }
            .map {
                LLMsProviderModel(
                    id: $0.name.replacingOccurrences(of: "models/", with: ""),
                    name: $0.displayName,
                    contextLength: $0.inputTokenLimit
                )
            }
    }

    func streamGenerateContent(
        apiBase: String,
        apiKey: String,
        model: String,
        systemInstruction: GeminiContent?,
        contents: [GeminiContent],
        tools: [GeminiTool]?
    ) -> AsyncThrowingStream<GeminiStreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try generateContentRequest(
                        apiBase: apiBase,
                        apiKey: apiKey,
                        model: model,
                        systemInstruction: systemInstruction,
                        contents: contents,
                        tools: tools
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse(serviceName)
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw APIError.serverStatus(serviceName, httpResponse.statusCode, try await responseBodyString(from: bytes))
                    }

                    var toolCallIndex = 0
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let delta = try Self.streamDelta(
                            fromServerSentEventLine: line,
                            toolCallIndex: &toolCallIndex,
                            serviceName: serviceName
                        ) else {
                            continue
                        }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated static func streamDelta(
        fromServerSentEventLine line: String,
        toolCallIndex: inout Int,
        serviceName: String
    ) throws -> GeminiStreamDelta? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("data:") else {
            return nil
        }

        let dataPrefixEndIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 5)
        let payload = trimmedLine[dataPrefixEndIndex...]
            .trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8) else {
            throw APIError.invalidResponse(serviceName)
        }

        let response: GenerateContentResponse
        do {
            response = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            throw APIError.invalidResponse(serviceName)
        }

        if let errorMessage = response.error?.message, !errorMessage.isEmpty {
            throw APIError.streamError(errorMessage)
        }

        var content = ""
        var toolCalls: [ChatToolCall] = []
        for part in response.candidates?.compactMap(\.content).flatMap(\.parts) ?? [] {
            switch part {
            case let .text(text):
                content += text
            case let .functionCall(id, name, args, thoughtSignature):
                let metadata = thoughtSignature.map {
                    [GeminiProviderError.thoughtSignatureMetadataKey: JSONValue.string($0)]
                } ?? [:]
                toolCalls.append(
                    ChatToolCall(
                        id: id ?? "gemini_tool_call_\(toolCallIndex)",
                        toolID: name,
                        arguments: args,
                        providerMetadata: metadata
                    )
                )
                toolCallIndex += 1
            case .inlineData,
                 .functionResponse:
                continue
            }
        }

        if content.isEmpty && toolCalls.isEmpty {
            if let message = Self.blockedPromptMessage(from: response) {
                throw APIError.streamError(message)
            }
            if let message = Self.blockedCandidateMessage(from: response) {
                throw APIError.streamError(message)
            }
        }

        let delta = GeminiStreamDelta(content: content, toolCalls: toolCalls)
        return content.isEmpty && toolCalls.isEmpty ? nil : delta
    }

    nonisolated private static func blockedPromptMessage(
        from response: GenerateContentResponse
    ) -> String? {
        guard let blockReason = response.promptFeedback?.blockReason,
              !blockReason.isEmpty else {
            return nil
        }

        if let message = response.promptFeedback?.blockReasonMessage,
           !message.isEmpty {
            return message
        }
        return String(localized: .providersErrorGeminiBlockedPromptFormat(blockReason))
    }

    nonisolated private static func blockedCandidateMessage(
        from response: GenerateContentResponse
    ) -> String? {
        let blockedReasons = Set([
            "SAFETY",
            "RECITATION",
            "BLOCKLIST",
            "PROHIBITED_CONTENT",
            "SPII",
            "LANGUAGE",
            "IMAGE_SAFETY",
            "IMAGE_PROHIBITED_CONTENT",
            "IMAGE_OTHER",
            "NO_IMAGE",
            "IMAGE_RECITATION",
            "UNEXPECTED_TOOL_CALL",
            "TOO_MANY_TOOL_CALLS",
            "MISSING_THOUGHT_SIGNATURE",
            "MALFORMED_FUNCTION_CALL",
            "MALFORMED_RESPONSE",
            "OTHER"
        ])

        for candidate in response.candidates ?? [] {
            guard let finishReason = candidate.finishReason,
                  blockedReasons.contains(finishReason) else {
                continue
            }

            if let message = candidate.finishMessage,
               !message.isEmpty {
                return message
            }
            return String(localized: .providersErrorGeminiStoppedGenerationFormat(finishReason))
        }

        return nil
    }

    private func modelsURL(apiBase: String) throws -> URL {
        try normalizedAPIBaseURL(apiBase: apiBase)
            .appendingPathComponent("models")
    }

    private func generateContentRequest(
        apiBase: String,
        apiKey: String,
        model: String,
        systemInstruction: GeminiContent?,
        contents: [GeminiContent],
        tools: [GeminiTool]?
    ) throws -> URLRequest {
        var request = URLRequest(url: try streamGenerateContentURL(apiBase: apiBase, model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(
            GenerateContentRequest(
                contents: contents,
                tools: tools,
                systemInstruction: systemInstruction
            )
        )
        return request
    }

    private func streamGenerateContentURL(apiBase: String, model: String) throws -> URL {
        let baseURL = try normalizedAPIBaseURL(apiBase: apiBase)
        let modelPath = model.hasPrefix("models/") ? model : "models/\(model)"
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidAPIBase(apiBase)
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "\(modelPath):streamGenerateContent"]
            .filter { !$0.isEmpty }
            .joined(separator: "/"))
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]

        guard let url = components.url else {
            throw APIError.invalidAPIBase(apiBase)
        }
        return url
    }

    private func responseBodyString(from bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            if !body.isEmpty {
                body.append("\n")
            }
            body.append(line)
            if body.count > 2_048 {
                break
            }
        }
        return body
    }

    private func normalizedAPIBaseURL(apiBase: String) throws -> URL {
        let trimmedAPIBase = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseString = trimmedAPIBase.isEmpty ? defaultAPIBase : trimmedAPIBase

        guard var components = URLComponents(string: baseString),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.query == nil,
              components.fragment == nil else {
            throw APIError.invalidAPIBase(baseString)
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedPath.isEmpty ? "" : "/\(trimmedPath)"
        guard let baseURL = components.url else {
            throw APIError.invalidAPIBase(baseString)
        }

        return baseURL
    }
}
