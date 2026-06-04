//
//  OpenRouterProvider.swift
//  UniLLMs
//
//  Created by ZayrickAPIClient to the unified LLMsProviderAdapter interface and isolates the concrete provider implementation.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let openRouter = LLMsProviderKind(rawValue: "openRouter")
}

struct OpenRouterProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "OpenRouter"
        static let defaultAPIBase = "https://openrouter.ai/api/v1"
    }

    enum ConfigurationKey {
        static let apiKey = "apiKey"
        static let apiBase = "apiBase"
    }

    let apiClient: OpenRouterAPIClient

    init(
        apiClient: OpenRouterAPIClient = OpenRouterAPIClient(
            serviceName: Metadata.displayName,
            defaultAPIBase: Metadata.defaultAPIBase
        )
    ) {
        self.apiClient = apiClient
    }

    var kind: LLMsProviderKind {
        .openRouter
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
            throw OpenRouterProviderError.missingAPIKey(displayName)
        }
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        let messages: [OpenRouterChatMessage]
        do {
            messages = try OpenRouterChatPromptRenderer.messages(
                for: request,
                supportsFileAttachments: true
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let tools = request.context.availableTools.map(OpenRouterChatTool.init(definition:))
                    let stream = apiClient.streamChatCompletion(
                        apiBase: configuration[ConfigurationKey.apiBase],
                        apiKey: configuration[ConfigurationKey.apiKey],
                        model: request.modelID,
                        messages: messages,
                        tools: tools,
                        sessionID: request.providerContext.sessionIdentifier?.value(maxLength: 256)
                    )
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
}

enum OpenRouterProviderError: LocalizedError, Equatable {
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

nonisolated enum OpenRouterChatPromptRenderer {
    static func messages(
        for request: ChatRequest,
        supportsFileAttachments: Bool
    ) throws -> [OpenRouterChatMessage] {
        let prompt = ChatPromptAssembler().assemblePrompt(from: request)
        guard let instructionText = prompt.instructionText else {
            return try prompt.messages.map {
                try OpenRouterChatMessage(
                    message: $0,
                    supportsFileAttachments: supportsFileAttachments
                )
            }
        }

        let instructionMessage = OpenRouterChatMessage(
            role: .system,
            content: .text(instructionText),
            toolCalls: nil,
            toolCallID: nil
        )
        let renderedMessages = try prompt.messages.map {
            try OpenRouterChatMessage(
                message: $0,
                supportsFileAttachments: supportsFileAttachments
            )
        }
        return [instructionMessage] + renderedMessages
    }
}

nonisolated extension OpenRouterChatMessage {
    init(
        message: ChatMessage,
        supportsFileAttachments: Bool = false
    ) throws {
        let content: OpenRouterMessageContent? = try Self.encodeContent(
            for: message,
            supportsFileAttachments: supportsFileAttachments
        )

        self.init(
            role: Self.role(for: message.role),
            content: content,
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
        supportsFileAttachments: Bool
    ) throws -> OpenRouterMessageContent? {
        let attachmentParts = try message.attachments.map {
            try Self.contentPart(
                for: $0,
                supportsFileAttachments: supportsFileAttachments
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

        var parts: [OpenRouterContentPart] = []
        if !message.content.isEmpty {
            parts.append(.text(message.content))
        }
        parts.append(contentsOf: attachmentParts)
        return .parts(parts)
    }

    private static func contentPart(
        for attachment: ChatAttachment,
        supportsFileAttachments: Bool
    ) throws -> OpenRouterContentPart {
        if attachment.kind == .file,
           !supportsFileAttachments {
            throw OpenRouterProviderError.unsupportedFileAttachments("OpenRouter")
        }

        guard let data = try? ChatAttachmentStore.shared.loadData(for: attachment),
              !data.isEmpty else {
            throw OpenRouterProviderError.missingAttachmentData(attachment.filename)
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
