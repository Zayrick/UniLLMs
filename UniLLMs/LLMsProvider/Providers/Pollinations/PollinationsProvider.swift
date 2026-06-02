//
//  PollinationsProvider.swift
//  UniLLMs
//
//  Native Pollinations provider adapter and OpenAI-compatible API surface.
//  Created by Codex on 2026/6/1.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let pollinations = LLMsProviderKind(rawValue: "pollinations")
}

struct PollinationsProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "Pollinations"
        static let defaultAPIBase = "https://gen.pollinations.ai/v1"
        static let freeAPIBase = "https://text.pollinations.ai/openai/v1"
    }

    enum ConfigurationKey {
        static let apiKey = "apiKey"
        static let apiBase = "apiBase"
    }

    let apiClient: PollinationsAPIClient

    init(
        apiClient: PollinationsAPIClient = PollinationsAPIClient(
            serviceName: Metadata.displayName,
            defaultAPIBase: Metadata.defaultAPIBase,
            defaultFreeAPIBase: Metadata.freeAPIBase
        )
    ) {
        self.apiClient = apiClient
    }

    var kind: LLMsProviderKind {
        .pollinations
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
                inputKind: .secret
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.apiBase,
                title: String(localized: .providerFieldApiBase),
                placeholder: Metadata.defaultAPIBase,
                binding: .configurationValue(ConfigurationKey.apiBase),
                inputKind: .url
            )
        ]
    }

    var modelSource: LLMsProviderModelSource {
        .remote
    }

    func configurationSummary(for configuration: LLMsProviderConfiguration) -> String? {
        let apiKey = configuration[ConfigurationKey.apiKey].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return String(localized: .providersSummaryFreeAnonymousTier)
        }
        return configuration[ConfigurationKey.apiBase]
    }

    func fetchModels(configuration: LLMsProviderConfiguration) async throws -> [LLMsProviderModel] {
        try await apiClient.fetchModels(
            apiBase: configuration[ConfigurationKey.apiBase],
            apiKey: configuration[ConfigurationKey.apiKey]
        )
    }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {
        _ = configuration
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        guard !Self.containsFileAttachments(request) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: PollinationsProviderError.unsupportedFileAttachments(displayName)
                )
            }
        }

        let messages: [PollinationsChatMessage]
        do {
            messages = try PollinationsChatPromptRenderer.messages(for: request)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        let tools = request.context.availableTools.map(PollinationsChatTool.init(definition:))
        let stream = apiClient.streamChatCompletion(
            apiBase: configuration[ConfigurationKey.apiBase],
            apiKey: configuration[ConfigurationKey.apiKey],
            model: request.modelID,
            messages: messages,
            tools: tools
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in stream {
                        continuation.yield(
                            ChatResponseDelta(
                                content: delta.content,
                                reasoning: delta.reasoning,
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
    }

    private static func containsFileAttachments(_ request: ChatRequest) -> Bool {
        request.messages.contains { message in
            message.attachments.contains { $0.kind == .file }
        }
    }
}

enum PollinationsProviderError: LocalizedError, Equatable {
    case missingAPIBase(String)
    case unsupportedFileAttachments(String)
    case missingAttachmentData(String)

    var errorDescription: String? {
        switch self {
        case let .missingAPIBase(displayName):
            return String(localized: .providersErrorMissingApiBaseFormat(displayName))
        case let .unsupportedFileAttachments(displayName):
            return String(localized: .providersErrorUnsupportedFileAttachmentsFormat(displayName))
        case let .missingAttachmentData(filename):
            return String(localized: .providersErrorMissingAttachmentDataFormat(filename))
        }
    }
}

nonisolated enum PollinationsChatPromptRenderer {
    static func messages(for request: ChatRequest) throws -> [PollinationsChatMessage] {
        let prompt = ChatPromptAssembler().assemblePrompt(from: request)
        guard let instructionText = prompt.instructionText else {
            return try prompt.messages.map(PollinationsChatMessage.init(message:))
        }

        let instructionMessage = PollinationsChatMessage(
            role: .system,
            content: .text(instructionText),
            toolCalls: nil,
            toolCallID: nil
        )
        let renderedMessages = try prompt.messages.map(PollinationsChatMessage.init(message:))
        return [instructionMessage] + renderedMessages
    }
}

nonisolated enum PollinationsMessageContent: Codable, Equatable {
    case text(String)
    case parts([PollinationsContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
            return
        }
        if let parts = try? container.decode([PollinationsContentPart].self) {
            self = .parts(parts)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: String(localized: .jsonErrorUnsupportedMessageContentPayload)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(string):
            try container.encode(string)
        case let .parts(parts):
            try container.encode(parts)
        }
    }
}

nonisolated enum PollinationsContentPart: Codable, Equatable {
    case text(String)
    case imageURL(url: String)

    nonisolated private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    nonisolated private struct ImageURLPayload: Codable, Equatable {
        var url: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            let payload = try container.decode(ImageURLPayload.self, forKey: .imageURL)
            self = .imageURL(url: payload.url)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: String(localized: .jsonErrorUnsupportedContentPartTypeFormat(type))
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(string):
            try container.encode("text", forKey: .type)
            try container.encode(string, forKey: .text)
        case let .imageURL(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: url), forKey: .imageURL)
        }
    }
}

nonisolated struct PollinationsChatMessage: Codable, Equatable {
    nonisolated enum Role: String, Codable {
        case user
        case assistant
        case system
        case tool
    }

    nonisolated struct ToolCall: Codable, Equatable {
        nonisolated struct Function: Codable, Equatable {
            var name: String
            var arguments: String
        }

        var id: String
        var type: String
        var function: Function
    }

    var role: Role
    var content: PollinationsMessageContent?
    var toolCalls: [ToolCall]?
    var toolCallID: String?

    nonisolated private enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    init(
        role: Role,
        content: PollinationsMessageContent?,
        toolCalls: [ToolCall]?,
        toolCallID: String?
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    init(message: ChatMessage) throws {
        self.init(
            role: Self.role(for: message.role),
            content: try Self.encodeContent(for: message),
            toolCalls: try message.toolCalls?.map {
                ToolCall(
                    id: $0.id,
                    type: "function",
                    function: ToolCall.Function(
                        name: $0.toolID,
                        arguments: try $0.validatedSerializedArguments()
                    )
                )
            },
            toolCallID: message.toolCallID
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let content {
            try container.encode(content, forKey: .content)
        } else if role == .assistant,
                  toolCalls?.isEmpty == false {
            try container.encodeNil(forKey: .content)
        }
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }

    private static func role(for role: ChatRole) -> Role {
        switch role {
        case .user:
            return .user
        case .assistant:
            return .assistant
        case .system:
            return .system
        case .tool:
            return .tool
        }
    }

    private static func encodeContent(for message: ChatMessage) throws -> PollinationsMessageContent? {
        let attachmentParts = try message.attachments.map(Self.contentPart)
        if attachmentParts.isEmpty {
            if message.role == .assistant,
               message.content.isEmpty,
               message.toolCalls?.isEmpty == false {
                return nil
            }
            return .text(message.content)
        }

        var parts: [PollinationsContentPart] = []
        if !message.content.isEmpty {
            parts.append(.text(message.content))
        }
        parts.append(contentsOf: attachmentParts)
        return .parts(parts)
    }

    private static func contentPart(for attachment: ChatAttachment) throws -> PollinationsContentPart {
        guard attachment.kind == .image else {
            throw PollinationsProviderError.unsupportedFileAttachments("Pollinations")
        }
        guard let data = try? ChatAttachmentStore.shared.loadData(for: attachment),
              !data.isEmpty else {
            throw PollinationsProviderError.missingAttachmentData(attachment.filename)
        }

        let mimeType = attachment.contentType.isEmpty
            ? "application/octet-stream"
            : attachment.contentType
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        return .imageURL(url: dataURL)
    }
}

nonisolated struct PollinationsChatTool: Encodable, Equatable {
    nonisolated struct Function: Encodable, Equatable {
        var name: String
        var description: String
        var parameters: JSONValue
    }

    var type = "function"
    var function: Function

    init(definition: ToolDefinition) {
        function = Function(
            name: definition.name,
            description: definition.summary,
            parameters: definition.parameters
        )
    }
}

nonisolated struct PollinationsToolCallDelta: Equatable {
    var index: Int
    var id: String?
    var name: String?
    var argumentsFragment: String
}

nonisolated struct PollinationsChatStreamDelta: Equatable {
    var content: String = ""
    var reasoning: String = ""
    var toolCallDeltas: [PollinationsToolCallDelta] = []
    var toolCalls: [ChatToolCall] = []

    var isEmpty: Bool {
        content.isEmpty && reasoning.isEmpty && toolCallDeltas.isEmpty && toolCalls.isEmpty
    }
}

nonisolated struct PollinationsAPIClient {
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
                return Self.serverStatusDescription(
                    serviceName: serviceName,
                    statusCode: statusCode,
                    message: message
                )
            case let .streamError(message):
                return message
            }
        }

        private static func serverStatusDescription(
            serviceName: String,
            statusCode: Int,
            message: String?
        ) -> String {
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch statusCode {
            case 401:
                guard !trimmedMessage.isEmpty else {
                    return String(localized: .providersErrorPollinationsUnauthorized(serviceName))
                }
                return String(localized: .providersErrorPollinationsUnauthorizedMessageFormat(serviceName, trimmedMessage))
            case 402:
                guard !trimmedMessage.isEmpty else {
                    return String(localized: .providersErrorPollinationsPaymentRequired(serviceName))
                }
                return String(localized: .providersErrorPollinationsPaymentRequiredMessageFormat(serviceName, trimmedMessage))
            case 429:
                guard !trimmedMessage.isEmpty else {
                    return String(localized: .providersErrorPollinationsRateLimited(serviceName))
                }
                return String(localized: .providersErrorPollinationsRateLimitedMessageFormat(serviceName, trimmedMessage))
            default:
                guard !trimmedMessage.isEmpty else {
                    return String(localized: .providersErrorHttpStatusFormat(serviceName, statusCode))
                }
                return String(localized: .providersErrorHttpStatusMessageFormat(serviceName, statusCode, trimmedMessage))
            }
        }
    }

    nonisolated private struct ModelsResponse: Decodable {
        var data: [Model]
    }

    nonisolated private struct Model: Decodable {
        var id: String
        var name: String?
        var contextLength: Int?

        nonisolated private enum CodingKeys: String, CodingKey {
            case id
            case name
            case contextLength = "context_length"
        }
    }

    nonisolated private struct FreeModel: Decodable {
        var name: String
        var description: String?
        var tier: String?
        var inputModalities: [String]?
        var outputModalities: [String]?
        var contextLength: Int?

        var isAnonymousTextModel: Bool {
            tier == "anonymous"
                && (inputModalities ?? []).contains("text")
                && (outputModalities ?? []).contains("text")
        }

        nonisolated private enum CodingKeys: String, CodingKey {
            case name
            case description
            case tier
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
            case contextLength = "context_length"
        }
    }

    nonisolated private struct ChatCompletionsRequest: Encodable {
        var model: String
        var messages: [PollinationsChatMessage]
        var stream: Bool
        var tools: [PollinationsChatTool]?
    }

    nonisolated private struct ChatCompletionChunk: Decodable {
        var choices: [Choice]?
        var error: ResponseError?

        nonisolated struct Choice: Decodable {
            var delta: Delta?
        }

        nonisolated struct Delta: Decodable {
            var content: String?
            var reasoning: String?
            var reasoningContent: String?
            var reasoningDetails: [ReasoningDetail]?
            var toolCalls: [ToolCall]?

            nonisolated private enum CodingKeys: String, CodingKey {
                case content
                case reasoning
                case reasoningContent = "reasoning_content"
                case reasoningDetails = "reasoning_details"
                case toolCalls = "tool_calls"
            }
        }

        nonisolated struct ReasoningDetail: Decodable {
            var text: String?
            var summary: String?
        }

        nonisolated struct ToolCall: Decodable {
            var index: Int?
            var id: String?
            var function: Function?

            nonisolated struct Function: Decodable {
                var name: String?
                var arguments: String?
            }
        }

        nonisolated struct ResponseError: Decodable {
            var message: String?
        }
    }

    var session: URLSession = .shared
    var serviceName: String = "Pollinations"
    var defaultAPIBase: String = "https://gen.pollinations.ai/v1"
    var defaultFreeAPIBase: String = "https://text.pollinations.ai/openai/v1"
    var freeModelsEndpoint: String = "https://text.pollinations.ai/models"

    func fetchModels(apiBase: String, apiKey: String) async throws -> [LLMsProviderModel] {
        let authorizationHeader = Self.bearerAuthorizationHeader(apiKey: apiKey)
        guard !authorizationHeader.isEmpty else {
            return try await fetchFreeModels()
        }

        var request = URLRequest(url: try modelsURL(apiBase: apiBase))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(serviceName)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverStatus(
                serviceName,
                httpResponse.statusCode,
                String(data: data, encoding: .utf8)
            )
        }

        return try Self.models(from: data)
    }

    private func fetchFreeModels() async throws -> [LLMsProviderModel] {
        guard let url = URL(string: freeModelsEndpoint) else {
            throw APIError.invalidAPIBase(freeModelsEndpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(serviceName)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverStatus(
                serviceName,
                httpResponse.statusCode,
                String(data: data, encoding: .utf8)
            )
        }

        return try Self.freeModels(from: data)
    }

    func streamChatCompletion(
        apiBase: String,
        apiKey: String,
        model: String,
        messages: [PollinationsChatMessage],
        tools: [PollinationsChatTool] = []
    ) -> AsyncThrowingStream<PollinationsChatStreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatCompletionsRequest(
                        apiBase: effectiveAPIBase(apiBase: apiBase, apiKey: apiKey),
                        apiKey: apiKey,
                        model: model,
                        messages: messages,
                        tools: tools
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse(serviceName)
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw APIError.serverStatus(
                            serviceName,
                            httpResponse.statusCode,
                            try await responseBodyString(from: bytes)
                        )
                    }

                    var toolCallAccumulator = PollinationsToolCallAccumulator()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if Self.isDoneServerSentEventLine(line) {
                            break
                        }
                        guard let delta = try Self.streamDelta(
                            fromServerSentEventLine: line,
                            serviceName: serviceName
                        ) else {
                            continue
                        }
                        toolCallAccumulator.append(delta.toolCallDeltas)
                        let responseDelta = PollinationsChatStreamDelta(
                            content: delta.content,
                            reasoning: delta.reasoning
                        )
                        if !responseDelta.isEmpty {
                            continuation.yield(responseDelta)
                        }
                    }

                    let toolCalls = toolCallAccumulator.completedToolCalls()
                    if !toolCalls.isEmpty {
                        continuation.yield(PollinationsChatStreamDelta(toolCalls: toolCalls))
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

    nonisolated static func models(from data: Data) throws -> [LLMsProviderModel] {
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map {
            LLMsProviderModel(
                id: $0.id,
                name: $0.name,
                contextLength: $0.contextLength
            )
        }
    }

    nonisolated static func freeModels(from data: Data) throws -> [LLMsProviderModel] {
        let decoded = try JSONDecoder().decode([FreeModel].self, from: data)
        return decoded
            .filter(\.isAnonymousTextModel)
            .map {
                LLMsProviderModel(
                    id: $0.name,
                    name: $0.description,
                    contextLength: $0.contextLength
                )
            }
    }

    nonisolated static func streamDelta(
        fromServerSentEventLine line: String,
        serviceName: String = "Pollinations"
    ) throws -> PollinationsChatStreamDelta? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty,
              !trimmedLine.hasPrefix(":"),
              trimmedLine.hasPrefix("data:") else {
            return nil
        }

        let dataPrefixEndIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 5)
        let payload = trimmedLine[dataPrefixEndIndex...]
            .trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else {
            return nil
        }
        guard let data = payload.data(using: .utf8) else {
            throw APIError.invalidResponse(serviceName)
        }

        let chunk: ChatCompletionChunk
        do {
            chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
        } catch {
            throw APIError.invalidResponse(serviceName)
        }

        if let errorMessage = chunk.error?.message,
           !errorMessage.isEmpty {
            throw APIError.streamError(errorMessage)
        }

        let deltas = chunk.choices?
            .compactMap(\.delta)
            .map(Self.streamDelta)
            ?? []
        let delta = PollinationsChatStreamDelta(
            content: deltas.map(\.content).joined(),
            reasoning: deltas.map(\.reasoning).joined(),
            toolCallDeltas: deltas.flatMap(\.toolCallDeltas)
        )
        return delta.isEmpty ? nil : delta
    }

    private func modelsURL(apiBase: String) throws -> URL {
        try normalizedAPIBaseURL(apiBase: apiBase)
            .appendingPathComponent("models")
    }

    private func effectiveAPIBase(apiBase: String, apiKey: String) -> String {
        let authorizationHeader = Self.bearerAuthorizationHeader(apiKey: apiKey)
        return authorizationHeader.isEmpty ? defaultFreeAPIBase : apiBase
    }

    private func chatCompletionsRequest(
        apiBase: String,
        apiKey: String,
        model: String,
        messages: [PollinationsChatMessage],
        tools: [PollinationsChatTool]
    ) throws -> URLRequest {
        var request = URLRequest(url: try chatCompletionsURL(apiBase: apiBase))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let authorizationHeader = Self.bearerAuthorizationHeader(apiKey: apiKey)
        if !authorizationHeader.isEmpty {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(
            ChatCompletionsRequest(
                model: model,
                messages: messages,
                stream: true,
                tools: tools.isEmpty ? nil : tools
            )
        )
        return request
    }

    private func chatCompletionsURL(apiBase: String) throws -> URL {
        try normalizedAPIBaseURL(apiBase: apiBase)
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
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

    nonisolated private static func streamDelta(
        from delta: ChatCompletionChunk.Delta
    ) -> PollinationsChatStreamDelta {
        let reasoningFromDetails = delta.reasoningDetails?
            .compactMap { detail in
                detail.text ?? detail.summary
            }
            .joined()
            ?? ""
        let reasoningFromStringFields = [
            delta.reasoning,
            delta.reasoningContent
        ]
            .compactMap { $0 }
            .joined()

        return PollinationsChatStreamDelta(
            content: delta.content ?? "",
            reasoning: reasoningFromDetails.isEmpty ? reasoningFromStringFields : reasoningFromDetails,
            toolCallDeltas: delta.toolCalls?.compactMap { toolCall in
                guard let index = toolCall.index else {
                    return nil
                }
                return PollinationsToolCallDelta(
                    index: index,
                    id: toolCall.id,
                    name: toolCall.function?.name,
                    argumentsFragment: toolCall.function?.arguments ?? ""
                )
            } ?? []
        )
    }

    nonisolated private static func isDoneServerSentEventLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]"
    }

    nonisolated private static func bearerAuthorizationHeader(apiKey: String) -> String {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAPIKey.isEmpty ? "" : "Bearer \(trimmedAPIKey)"
    }
}

nonisolated private struct PollinationsToolCallAccumulator {
    nonisolated private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var partials: [Int: PartialToolCall] = [:]

    mutating func append(_ deltas: [PollinationsToolCallDelta]) {
        for delta in deltas {
            var partial = partials[delta.index] ?? PartialToolCall()
            if let id = delta.id, !id.isEmpty {
                partial.id = id
            }
            if let name = delta.name, !name.isEmpty {
                partial.name = name
            }
            partial.arguments += delta.argumentsFragment
            partials[delta.index] = partial
        }
    }

    func completedToolCalls() -> [ChatToolCall] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index],
                  let name = partial.name else {
                return nil
            }
            return ChatToolCall(
                id: partial.id ?? "pollinations_tool_call_\(index)",
                toolID: name,
                serializedArguments: partial.arguments
            )
        }
    }
}
