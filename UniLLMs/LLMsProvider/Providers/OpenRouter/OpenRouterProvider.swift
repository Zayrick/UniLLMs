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
                title: "Name",
                placeholder: displayName,
                binding: .providerName,
                inputKind: .plain
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.apiKey,
                title: "Key",
                placeholder: "OpenRouter API Key",
                binding: .configurationValue(ConfigurationKey.apiKey),
                inputKind: .secret,
                isRequired: true
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.apiBase,
                title: "API Base",
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
        let messages = request.messages.map(OpenRouterChatMessage.init(message:))
        let tools = request.context.availableTools.map(OpenRouterChatTool.init(definition:))
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
}

enum OpenRouterProviderError: LocalizedError, Equatable {
    case missingAPIKey(String)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(displayName):
            return "Add an API key for \(displayName) in Settings first."
        }
    }
}

nonisolated extension OpenRouterChatMessage {
    init(message: ChatMessage) {
        let content = message.role == .assistant && message.content.isEmpty
            ? nil
            : message.content

        self.init(
            role: Role(rawValue: message.role.rawValue) ?? .user,
            content: content,
            toolCalls: message.toolCalls?.map {
                ToolCall(
                    id: $0.id,
                    type: "function",
                    function: ToolCall.Function(
                        name: $0.toolID,
                        arguments: $0.arguments
                    )
                )
            },
            toolCallID: message.toolCallID
        )
    }
}
