//
//  OpenAICompatibleChatCompletionsSupport.swift
//  UniLLMs
//
//  Shared Chat Completions protocol support for OpenAI-compatible providers.
//  Created by Codex on 2026/6/4.
//

import Foundation

nonisolated struct OpenAICompatibleChatPromptRenderingOptions {
    var instructionRole: OpenAICompatibleChatMessage.Role
    var supportsFileAttachments: Bool
    var serviceName: String

    init(
        instructionRole: OpenAICompatibleChatMessage.Role = .system,
        supportsFileAttachments: Bool = false,
        serviceName: String = String(localized: .providersOpenaiCompatibleDisplayName)
    ) {
        self.instructionRole = instructionRole
        self.supportsFileAttachments = supportsFileAttachments
        self.serviceName = serviceName
    }
}

nonisolated enum OpenAICompatibleChatPromptRenderer {
    static func messages(
        for request: ChatRequest,
        options: OpenAICompatibleChatPromptRenderingOptions = OpenAICompatibleChatPromptRenderingOptions()
    ) throws -> [OpenAICompatibleChatMessage] {
        let prompt = ChatPromptAssembler().assemblePrompt(from: request)
        guard let instructionText = prompt.instructionText else {
            return try prompt.messages.map {
                try OpenAICompatibleChatMessage(
                    message: $0,
                    supportsFileAttachments: options.supportsFileAttachments,
                    serviceName: options.serviceName
                )
            }
        }

        let instructionMessage = OpenAICompatibleChatMessage(
            role: options.instructionRole,
            content: .text(instructionText),
            toolCalls: nil,
            toolCallID: nil
        )
        let renderedMessages = try prompt.messages.map {
            try OpenAICompatibleChatMessage(
                message: $0,
                supportsFileAttachments: options.supportsFileAttachments,
                serviceName: options.serviceName
            )
        }
        return [instructionMessage] + renderedMessages
    }
}

nonisolated enum OpenAICompatibleMessageContent: Codable, Equatable {
    case text(String)
    case parts([OpenAICompatibleContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
            return
        }
        if let parts = try? container.decode([OpenAICompatibleContentPart].self) {
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

nonisolated enum OpenAICompatibleContentPart: Codable, Equatable {
    case text(String)
    case imageURL(url: String)
    case file(filename: String, fileData: String)

    nonisolated private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case file
    }

    nonisolated private struct ImageURLPayload: Codable, Equatable {
        var url: String
    }

    nonisolated private struct FilePayload: Codable, Equatable {
        var filename: String
        var fileData: String

        nonisolated private enum CodingKeys: String, CodingKey {
            case filename
            case fileData = "file_data"
        }
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
        case "file":
            let payload = try container.decode(FilePayload.self, forKey: .file)
            self = .file(filename: payload.filename, fileData: payload.fileData)
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
        case let .file(filename, fileData):
            try container.encode("file", forKey: .type)
            try container.encode(
                FilePayload(filename: filename, fileData: fileData),
                forKey: .file
            )
        }
    }
}

nonisolated struct OpenAICompatibleChatMessage: Codable, Equatable {
    nonisolated enum Role: String, Codable {
        case user
        case assistant
        case system
        case developer
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
    var content: OpenAICompatibleMessageContent?
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
        content: OpenAICompatibleMessageContent?,
        toolCalls: [ToolCall]?,
        toolCallID: String?
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    init(
        message: ChatMessage,
        supportsFileAttachments: Bool = false,
        serviceName: String = String(localized: .providersOpenaiCompatibleDisplayName)
    ) throws {
        self.init(
            role: Self.role(for: message.role),
            content: try Self.encodeContent(
                for: message,
                supportsFileAttachments: supportsFileAttachments,
                serviceName: serviceName
            ),
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

    private static func encodeContent(
        for message: ChatMessage,
        supportsFileAttachments: Bool,
        serviceName: String
    ) throws -> OpenAICompatibleMessageContent? {
        let attachmentParts = try message.attachments.map {
            try Self.contentPart(
                for: $0,
                supportsFileAttachments: supportsFileAttachments,
                serviceName: serviceName
            )
        }
        if attachmentParts.isEmpty {
            if message.role == .assistant,
               message.content.isEmpty,
               message.toolCalls?.isEmpty == false {
                return nil
            }
            return .text(message.content)
        }

        var parts: [OpenAICompatibleContentPart] = []
        if !message.content.isEmpty {
            parts.append(.text(message.content))
        }
        parts.append(contentsOf: attachmentParts)
        return .parts(parts)
    }

    private static func contentPart(
        for attachment: ChatAttachment,
        supportsFileAttachments: Bool,
        serviceName: String
    ) throws -> OpenAICompatibleContentPart {
        if attachment.kind == .file,
           !supportsFileAttachments {
            throw OpenAICompatibleChatSupportError.unsupportedFileAttachments(serviceName)
        }

        guard let data = try? ChatAttachmentStore.shared.loadData(for: attachment),
              !data.isEmpty else {
            throw OpenAICompatibleChatSupportError.missingAttachmentData(attachment.filename)
        }

        let base64 = data.base64EncodedString()
        let mimeType = attachment.contentType.isEmpty
            ? "application/octet-stream"
            : attachment.contentType
        let dataURL = "data:\(mimeType);base64,\(base64)"

        switch attachment.kind {
        case .image:
            return .imageURL(url: dataURL)
        case .file:
            return .file(filename: attachment.filename, fileData: dataURL)
        }
    }
}

nonisolated struct OpenAICompatibleChatTool: Encodable, Equatable {
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

nonisolated struct OpenAICompatibleToolCallDelta: Equatable {
    var index: Int
    var id: String?
    var name: String?
    var argumentsFragment: String
}

nonisolated struct OpenAICompatibleChatStreamDelta: Equatable {
    var content: String = ""
    var reasoning: String = ""
    var toolCallDeltas: [OpenAICompatibleToolCallDelta] = []
    var toolCalls: [ChatToolCall] = []

    var isEmpty: Bool {
        content.isEmpty && reasoning.isEmpty && toolCallDeltas.isEmpty && toolCalls.isEmpty
    }
}

nonisolated struct OpenAICompatibleChatProviderPreferences: Encodable, Equatable {
    var requireParameters: Bool

    nonisolated private enum CodingKeys: String, CodingKey {
        case requireParameters = "require_parameters"
    }
}

nonisolated enum OpenAICompatibleAuthorizationPolicy: Equatable {
    case omitWhenBlank
    case includeBearerEvenWhenBlank
}

nonisolated enum OpenAICompatibleChatSupportError: LocalizedError, Equatable {
    case unsupportedFileAttachments(String)
    case missingAttachmentData(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFileAttachments(displayName):
            return String(localized: .providersErrorUnsupportedFileAttachmentsFormat(displayName))
        case let .missingAttachmentData(filename):
            return String(localized: .providersErrorMissingAttachmentDataFormat(filename))
        }
    }
}

nonisolated struct OpenAICompatibleAPIClient {
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

    nonisolated private struct ChatCompletionsRequest: Encodable {
        var model: String
        var messages: [OpenAICompatibleChatMessage]
        var stream: Bool
        var tools: [OpenAICompatibleChatTool]?
        var provider: OpenAICompatibleChatProviderPreferences?
        var sessionID: String?

        nonisolated private enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case tools
            case provider
            case sessionID = "session_id"
        }
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
            var type: String?
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

    var session: URLSession
    var serviceName: String
    var defaultAPIBase: String

    init(
        session: URLSession = .shared,
        serviceName: String = String(localized: .providersOpenaiCompatibleDisplayName),
        defaultAPIBase: String = ""
    ) {
        self.session = session
        self.serviceName = serviceName
        self.defaultAPIBase = defaultAPIBase
    }

    func fetchModels(
        apiBase: String,
        apiKey: String,
        includeModelMetadata: Bool = false,
        authorizationPolicy: OpenAICompatibleAuthorizationPolicy = .omitWhenBlank
    ) async throws -> [LLMsProviderModel] {
        var request = URLRequest(url: try normalizedAPIBaseURL(apiBase: apiBase).appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorizationHeader = Self.authorizationHeader(
            apiKey: apiKey,
            policy: authorizationPolicy
        ) {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(serviceName)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverStatus(serviceName, httpResponse.statusCode, String(data: data, encoding: .utf8))
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map {
            LLMsProviderModel(
                id: $0.id,
                name: includeModelMetadata ? $0.name : nil,
                contextLength: includeModelMetadata ? $0.contextLength : nil
            )
        }
    }

    func streamChatCompletion(
        apiBase: String,
        apiKey: String,
        model: String,
        messages: [OpenAICompatibleChatMessage],
        tools: [OpenAICompatibleChatTool] = [],
        providerPreferences: OpenAICompatibleChatProviderPreferences? = nil,
        sessionID: String? = nil,
        authorizationPolicy: OpenAICompatibleAuthorizationPolicy = .omitWhenBlank,
        includesReasoningDetails: Bool = false,
        fallbackToolCallIDPrefix: String = "openai_compatible_tool_call_"
    ) -> AsyncThrowingStream<OpenAICompatibleChatStreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatCompletionsRequest(
                        apiBase: apiBase,
                        apiKey: apiKey,
                        model: model,
                        messages: messages,
                        tools: tools,
                        providerPreferences: providerPreferences,
                        sessionID: sessionID,
                        authorizationPolicy: authorizationPolicy
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse(serviceName)
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw APIError.serverStatus(serviceName, httpResponse.statusCode, try await responseBodyString(from: bytes))
                    }

                    var toolCallAccumulator = OpenAICompatibleToolCallAccumulator(
                        fallbackIDPrefix: fallbackToolCallIDPrefix
                    )
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if Self.isDoneServerSentEventLine(line) {
                            break
                        }
                        guard let delta = try Self.streamDelta(
                            fromServerSentEventLine: line,
                            serviceName: serviceName,
                            includesReasoningDetails: includesReasoningDetails
                        ) else {
                            continue
                        }
                        toolCallAccumulator.append(delta.toolCallDeltas)
                        let responseDelta = OpenAICompatibleChatStreamDelta(
                            content: delta.content,
                            reasoning: delta.reasoning
                        )
                        if !responseDelta.isEmpty {
                            continuation.yield(responseDelta)
                        }
                    }

                    let toolCalls = toolCallAccumulator.completedToolCalls()
                    if !toolCalls.isEmpty {
                        continuation.yield(OpenAICompatibleChatStreamDelta(toolCalls: toolCalls))
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
        serviceName: String = String(localized: .providersOpenaiCompatibleDisplayName),
        includesReasoningDetails: Bool = false
    ) throws -> OpenAICompatibleChatStreamDelta? {
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
            .map {
                Self.streamDelta(
                    from: $0,
                    includesReasoningDetails: includesReasoningDetails
                )
            }
            ?? []
        let delta = OpenAICompatibleChatStreamDelta(
            content: deltas.map(\.content).joined(),
            reasoning: deltas.map(\.reasoning).joined(),
            toolCallDeltas: deltas.flatMap(\.toolCallDeltas)
        )
        return delta.isEmpty ? nil : delta
    }

    private func chatCompletionsRequest(
        apiBase: String,
        apiKey: String,
        model: String,
        messages: [OpenAICompatibleChatMessage],
        tools: [OpenAICompatibleChatTool],
        providerPreferences: OpenAICompatibleChatProviderPreferences?,
        sessionID: String?,
        authorizationPolicy: OpenAICompatibleAuthorizationPolicy
    ) throws -> URLRequest {
        var request = URLRequest(url: try normalizedAPIBaseURL(apiBase: apiBase).appendingPathComponent("chat").appendingPathComponent("completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let authorizationHeader = Self.authorizationHeader(
            apiKey: apiKey,
            policy: authorizationPolicy
        ) {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionsRequest(
                model: model,
                messages: messages,
                stream: true,
                tools: tools.isEmpty ? nil : tools,
                provider: providerPreferences,
                sessionID: sessionID
            )
        )
        return request
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
        from delta: ChatCompletionChunk.Delta,
        includesReasoningDetails: Bool
    ) -> OpenAICompatibleChatStreamDelta {
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

        return OpenAICompatibleChatStreamDelta(
            content: delta.content ?? "",
            reasoning: includesReasoningDetails && !reasoningFromDetails.isEmpty
                ? reasoningFromDetails
                : reasoningFromStringFields,
            toolCallDeltas: delta.toolCalls?.compactMap { toolCall in
                guard let index = toolCall.index else {
                    return nil
                }
                return OpenAICompatibleToolCallDelta(
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

    nonisolated private static func authorizationHeader(
        apiKey: String,
        policy: OpenAICompatibleAuthorizationPolicy
    ) -> String? {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch policy {
        case .omitWhenBlank:
            return trimmedAPIKey.isEmpty ? nil : "Bearer \(trimmedAPIKey)"
        case .includeBearerEvenWhenBlank:
            return "Bearer \(trimmedAPIKey)"
        }
    }
}

nonisolated private struct OpenAICompatibleToolCallAccumulator {
    nonisolated private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var partials: [Int: PartialToolCall] = [:]
    private let fallbackIDPrefix: String

    init(fallbackIDPrefix: String) {
        self.fallbackIDPrefix = fallbackIDPrefix
    }

    mutating func append(_ deltas: [OpenAICompatibleToolCallDelta]) {
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
                id: partial.id ?? "\(fallbackIDPrefix)\(index)",
                toolID: name,
                serializedArguments: partial.arguments
            )
        }
    }
}
