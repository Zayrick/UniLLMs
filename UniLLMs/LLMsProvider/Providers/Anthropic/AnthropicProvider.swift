//
//  AnthropicProvider.swift
//  UniLLMs
//
//  Native Anthropic provider adapter.
//  Created by Codex on 2026/5/22.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let anthropic = LLMsProviderKind(rawValue: "anthropic")
}

struct AnthropicProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "Anthropic"
        static let defaultAPIBase = "https://api.anthropic.com/v1"
        static let defaultAPIVersion = "2023-06-01"
        static let defaultMaxTokens = "4096"
    }

    enum ConfigurationKey {
        static let apiKey = "apiKey"
        static let apiBase = "apiBase"
        static let apiVersion = "apiVersion"
        static let maxTokens = "maxTokens"
    }

    let apiClient: AnthropicAPIClient

    init(
        apiClient: AnthropicAPIClient = AnthropicAPIClient(
            serviceName: Metadata.displayName,
            defaultAPIBase: Metadata.defaultAPIBase
        )
    ) {
        self.apiClient = apiClient
    }

    var kind: LLMsProviderKind {
        .anthropic
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
                ConfigurationKey.apiBase: Metadata.defaultAPIBase,
                ConfigurationKey.apiVersion: Metadata.defaultAPIVersion,
                ConfigurationKey.maxTokens: Metadata.defaultMaxTokens
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
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.apiVersion,
                title: String(localized: .providerFieldApiVersion),
                placeholder: Metadata.defaultAPIVersion,
                binding: .configurationValue(ConfigurationKey.apiVersion),
                inputKind: .plain,
                isRequired: true
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.maxTokens,
                title: String(localized: .providerFieldMaxTokens),
                placeholder: Metadata.defaultMaxTokens,
                binding: .configurationValue(ConfigurationKey.maxTokens),
                inputKind: .plain,
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
            apiKey: configuration[ConfigurationKey.apiKey],
            apiVersion: apiVersion(from: configuration)
        )
    }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {
        guard !configuration[ConfigurationKey.apiKey].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnthropicProviderError.missingAPIKey(displayName)
        }
        guard maxTokens(from: configuration) != nil else {
            throw AnthropicProviderError.invalidMaxTokens
        }
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        do {
            guard !LLMsProviderStreamSupport.containsFileAttachments(request) else {
                throw AnthropicProviderError.unsupportedFileAttachments(displayName)
            }

            let renderedPrompt = try AnthropicChatPromptRenderer.render(request: request)
            let stream = apiClient.streamMessages(
                apiBase: configuration[ConfigurationKey.apiBase],
                apiKey: configuration[ConfigurationKey.apiKey],
                apiVersion: apiVersion(from: configuration),
                model: request.modelID,
                maxTokens: maxTokens(from: configuration) ?? Int(Metadata.defaultMaxTokens) ?? 4096,
                system: renderedPrompt.system,
                messages: renderedPrompt.messages,
                tools: request.context.availableTools.map(AnthropicTool.init(definition:))
            )

            return LLMsProviderStreamSupport.chatResponseStream(from: stream)
        } catch {
            return LLMsProviderStreamSupport.failedChatResponseStream(error)
        }
    }

    private func apiVersion(from configuration: LLMsProviderConfiguration) -> String {
        let trimmedValue = configuration[ConfigurationKey.apiVersion]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? Metadata.defaultAPIVersion : trimmedValue
    }

    private func maxTokens(from configuration: LLMsProviderConfiguration) -> Int? {
        let trimmedValue = configuration[ConfigurationKey.maxTokens]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmedValue.isEmpty ? Metadata.defaultMaxTokens : trimmedValue),
              value > 0 else {
            return nil
        }

        return value
    }
}

enum AnthropicProviderError: LocalizedError, Equatable {
    case missingAPIKey(String)
    case invalidMaxTokens
    case unsupportedFileAttachments(String)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(displayName):
            return String(localized: .providersErrorMissingApiKeyFormat(displayName))
        case .invalidMaxTokens:
            return String(localized: .providersErrorInvalidMaxTokens)
        case let .unsupportedFileAttachments(displayName):
            return String(localized: .providersErrorUnsupportedFileAttachmentsFormat(displayName))
        }
    }
}

nonisolated struct AnthropicRenderedPrompt: Equatable {
    var system: String?
    var messages: [AnthropicMessage]
}

nonisolated enum AnthropicChatPromptRenderer {
    static func render(
        request: ChatRequest,
        attachmentPayloadLoader: LLMsProviderAttachmentPayloadLoader = .shared
    ) throws -> AnthropicRenderedPrompt {
        let prompt = ChatPromptAssembler().assemblePrompt(from: request)
        var messages: [AnthropicMessage] = []
        var pendingToolResults: [AnthropicContentBlock] = []

        func flushToolResults() {
            guard !pendingToolResults.isEmpty else {
                return
            }

            messages.append(
                AnthropicMessage(role: .user, content: pendingToolResults)
            )
            pendingToolResults = []
        }

        for message in prompt.messages {
            if message.role == .tool {
                pendingToolResults.append(.toolResult(message))
                continue
            }

            flushToolResults()

            switch message.role {
            case .user:
                messages.append(
                    AnthropicMessage(
                        role: .user,
                        content: try userContentBlocks(
                            for: message,
                            attachmentPayloadLoader: attachmentPayloadLoader
                        )
                    )
                )
            case .assistant:
                messages.append(
                    AnthropicMessage(
                        role: .assistant,
                        content: assistantContentBlocks(for: message)
                    )
                )
            case .system:
                messages.append(
                    AnthropicMessage(
                        role: .user,
                        content: [.text(message.content)]
                    )
                )
            case .tool:
                break
            }
        }

        flushToolResults()
        return AnthropicRenderedPrompt(system: prompt.instructionText, messages: messages)
    }

    private static func userContentBlocks(
        for message: ChatMessage,
        attachmentPayloadLoader: LLMsProviderAttachmentPayloadLoader
    ) throws -> [AnthropicContentBlock] {
        var blocks: [AnthropicContentBlock] = []
        for attachment in message.attachments {
            let payload = try attachmentPayloadLoader.loadPayload(for: attachment)

            switch attachment.kind {
            case .image:
                blocks.append(.imageBase64(mediaType: payload.contentType, data: payload.base64EncodedData))
            case .file:
                throw AnthropicProviderError.unsupportedFileAttachments("Anthropic")
            }
        }

        if !message.content.isEmpty {
            blocks.append(.text(message.content))
        }

        return blocks.isEmpty ? [.text("")] : blocks
    }

    private static func assistantContentBlocks(for message: ChatMessage) -> [AnthropicContentBlock] {
        var blocks: [AnthropicContentBlock] = []
        if !message.content.isEmpty {
            blocks.append(.text(message.content))
        }
        for toolCall in message.toolCalls ?? [] {
            blocks.append(.toolUse(toolCall))
        }
        return blocks.isEmpty ? [.text("")] : blocks
    }
}

nonisolated struct AnthropicMessage: Encodable, Equatable {
    nonisolated enum Role: String, Encodable {
        case user
        case assistant
    }

    var role: Role
    var content: [AnthropicContentBlock]
}

nonisolated enum AnthropicContentBlock: Encodable, Equatable {
    case text(String)
    case imageBase64(mediaType: String, data: String)
    case toolUse(ChatToolCall)
    case toolResult(ChatMessage)

    nonisolated private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case id
        case name
        case input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    nonisolated private struct ImageSource: Encodable, Equatable {
        var type = "base64"
        var mediaType: String
        var data: String

        nonisolated private enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageBase64(mediaType, data):
            try container.encode("image", forKey: .type)
            try container.encode(
                ImageSource(
                    mediaType: mediaType.isEmpty ? "application/octet-stream" : mediaType,
                    data: data
                ),
                forKey: .source
            )
        case let .toolUse(toolCall):
            try container.encode("tool_use", forKey: .type)
            try container.encode(toolCall.id, forKey: .id)
            try container.encode(toolCall.toolID, forKey: .name)
            try container.encode(toolCall.arguments, forKey: .input)
        case let .toolResult(message):
            try container.encode("tool_result", forKey: .type)
            try container.encode(message.toolCallID ?? "", forKey: .toolUseID)
            try container.encode(message.content, forKey: .content)
            if message.toolStatus == .error {
                try container.encode(true, forKey: .isError)
            }
        }
    }
}

nonisolated struct AnthropicTool: Encodable, Equatable {
    var name: String
    var description: String
    var inputSchema: JSONValue

    nonisolated private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    init(definition: ToolDefinition) {
        name = definition.name
        description = definition.summary
        inputSchema = definition.parameters
    }
}

nonisolated struct AnthropicStreamDelta: Equatable, LLMsProviderStreamSupport.ChatResponseDeltaConvertible {
    var content: String = ""
    var toolCalls: [ChatToolCall] = []

    var chatResponseDelta: ChatResponseDelta {
        ChatResponseDelta(
            content: content,
            toolCalls: toolCalls
        )
    }
}

nonisolated struct AnthropicAPIClient {
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
        var displayName: String?

        nonisolated private enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    nonisolated private struct MessagesRequest: Encodable {
        var model: String
        var maxTokens: Int
        var system: String?
        var messages: [AnthropicMessage]
        var stream: Bool
        var tools: [AnthropicTool]?

        nonisolated private enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case stream
            case tools
        }
    }

    nonisolated private struct StreamEvent: Decodable {
        var type: String
        var index: Int?
        var contentBlock: ContentBlock?
        var delta: Delta?
        var error: StreamError?

        nonisolated private enum CodingKeys: String, CodingKey {
            case type
            case index
            case contentBlock = "content_block"
            case delta
            case error
        }

        nonisolated struct ContentBlock: Decodable {
            var type: String
            var id: String?
            var name: String?
        }

        nonisolated struct Delta: Decodable {
            var type: String
            var text: String?
            var partialJSON: String?
            var thinking: String?

            nonisolated private enum CodingKeys: String, CodingKey {
                case type
                case text
                case partialJSON = "partial_json"
                case thinking
            }
        }

        nonisolated struct StreamError: Decodable {
            var message: String?
        }
    }

    var session: URLSession = .shared
    var serviceName: String
    var defaultAPIBase: String

    func fetchModels(
        apiBase: String,
        apiKey: String,
        apiVersion: String
    ) async throws -> [LLMsProviderModel] {
        var request = URLRequest(url: try normalizedAPIBaseURL(apiBase: apiBase).appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")

        let (data, response) = try await session.data(for: request)
        try LLMsProviderHTTPResponseValidator.validateDataResponse(
            response: response,
            data: data,
            serviceName: serviceName,
            invalidResponseError: APIError.invalidResponse,
            serverStatusError: APIError.serverStatus
        )

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map {
            LLMsProviderModel(id: $0.id, name: $0.displayName)
        }
    }

    func streamMessages(
        apiBase: String,
        apiKey: String,
        apiVersion: String,
        model: String,
        maxTokens: Int,
        system: String?,
        messages: [AnthropicMessage],
        tools: [AnthropicTool]
    ) -> AsyncThrowingStream<AnthropicStreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try messagesRequest(
                        apiBase: apiBase,
                        apiKey: apiKey,
                        apiVersion: apiVersion,
                        model: model,
                        maxTokens: maxTokens,
                        system: system,
                        messages: messages,
                        tools: tools
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    try await LLMsProviderHTTPResponseValidator.validateStreamingResponse(
                        response: response,
                        bytes: bytes,
                        serviceName: serviceName,
                        invalidResponseError: APIError.invalidResponse,
                        serverStatusError: APIError.serverStatus
                    )

                    var toolCallAccumulator = AnthropicToolCallAccumulator()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let delta = try Self.streamDelta(
                            fromServerSentEventLine: line,
                            accumulator: &toolCallAccumulator,
                            serviceName: serviceName
                        ) else {
                            continue
                        }

                        if !delta.content.isEmpty {
                            continuation.yield(delta)
                        }
                    }

                    let toolCalls = toolCallAccumulator.completedToolCalls()
                    if !toolCalls.isEmpty {
                        continuation.yield(AnthropicStreamDelta(toolCalls: toolCalls))
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
        accumulator: inout AnthropicToolCallAccumulator,
        serviceName: String
    ) throws -> AnthropicStreamDelta? {
        guard let event = try ServerSentEventJSONDecoder.decode(
            StreamEvent.self,
            from: line,
            skipsDoneSignal: false,
            invalidPayloadError: { APIError.invalidResponse(serviceName) }
        ) else {
            return nil
        }

        if let errorMessage = event.error?.message, !errorMessage.isEmpty {
            throw APIError.streamError(errorMessage)
        }

        if event.type == "content_block_start",
           event.contentBlock?.type == "tool_use",
           let index = event.index {
            accumulator.start(
                index: index,
                id: event.contentBlock?.id,
                name: event.contentBlock?.name
            )
            return nil
        }

        guard event.type == "content_block_delta",
              let delta = event.delta else {
            return nil
        }

        switch delta.type {
        case "text_delta":
            return AnthropicStreamDelta(content: delta.text ?? "")
        case "input_json_delta":
            if let index = event.index {
                accumulator.append(
                    index: index,
                    argumentsFragment: delta.partialJSON ?? ""
                )
            }
            return nil
        default:
            return nil
        }
    }

    private func messagesRequest(
        apiBase: String,
        apiKey: String,
        apiVersion: String,
        model: String,
        maxTokens: Int,
        system: String?,
        messages: [AnthropicMessage],
        tools: [AnthropicTool]
    ) throws -> URLRequest {
        var request = URLRequest(url: try normalizedAPIBaseURL(apiBase: apiBase).appendingPathComponent("messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(
            MessagesRequest(
                model: model,
                maxTokens: maxTokens,
                system: system,
                messages: messages,
                stream: true,
                tools: tools.isEmpty ? nil : tools
            )
        )
        return request
    }

    private func normalizedAPIBaseURL(apiBase: String) throws -> URL {
        let baseString = LLMsProviderAPIBaseURL.effectiveString(
            apiBase: apiBase,
            defaultAPIBase: defaultAPIBase
        )
        guard let baseURL = LLMsProviderAPIBaseURL.normalizedURL(baseString: baseString) else {
            throw APIError.invalidAPIBase(baseString)
        }
        return baseURL
    }
}

nonisolated struct AnthropicToolCallAccumulator: Equatable {
    nonisolated private struct PartialToolCall: Equatable {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var partials: [Int: PartialToolCall] = [:]

    mutating func start(index: Int, id: String?, name: String?) {
        var partial = partials[index] ?? PartialToolCall()
        partial.id = id
        partial.name = name
        partials[index] = partial
    }

    mutating func append(index: Int, argumentsFragment: String) {
        var partial = partials[index] ?? PartialToolCall()
        partial.arguments += argumentsFragment
        partials[index] = partial
    }

    func completedToolCalls() -> [ChatToolCall] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index],
                  let name = partial.name else {
                return nil
            }

            return ChatToolCall(
                id: partial.id ?? "anthropic_tool_call_\(index)",
                toolID: name,
                serializedArguments: partial.arguments
            )
        }
    }
}
