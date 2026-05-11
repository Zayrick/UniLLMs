//
//  OpenRouterProvider.swift
//  UniLLMs
//
//  Created by ZayrickAPIClient to the unified LLMsProviderAdapter interface and isolates the concrete provider implementation.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

struct OpenRouterProvider: LLMsProviderAdapter {
    let apiClient: OpenRouterAPIClient

    init(apiClient: OpenRouterAPIClient = OpenRouterAPIClient()) {
        self.apiClient = apiClient
    }

    var kind: LLMsProviderKind {
        .openRouter
    }

    var displayName: String {
        LLMsProviderRecord.openRouterDisplayName
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.modelList, .streamingChat]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration(
            apiKey: "",
            apiBase: LLMsProviderRecord.openRouterDefaultAPIBase
        )
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        [
            LLMsProviderConfigurationField(
                id: "name",
                title: "Name",
                placeholder: displayName,
                valueKey: .providerName,
                inputKind: .plain
            ),
            LLMsProviderConfigurationField(
                id: "apiKey",
                title: "Key",
                placeholder: "OpenRouter API Key",
                valueKey: .apiKey,
                inputKind: .secret
            ),
            LLMsProviderConfigurationField(
                id: "apiBase",
                title: "API Base",
                placeholder: LLMsProviderRecord.openRouterDefaultAPIBase,
                valueKey: .apiBase,
                inputKind: .url
            )
        ]
    }

    func fetchModels(configuration: LLMsProviderConfiguration) async throws -> [LLMsProviderModel] {
        try await apiClient.fetchModels(
            apiBase: configuration.apiBase,
            apiKey: configuration.apiKey
        )
    }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterProviderError.missingAPIKey(displayName)
        }
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        let messages = request.messages.map(OpenRouterChatMessage.init(message:))
        let stream = apiClient.streamChatCompletion(
            apiBase: configuration.apiBase,
            apiKey: configuration.apiKey,
            model: request.modelID,
            messages: messages
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in stream {
                        continuation.yield(
                            ChatResponseDelta(
                                content: delta.content,
                                reasoning: delta.reasoning
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

private extension OpenRouterChatMessage {
    init(message: ChatMessage) {
        self.init(
            role: Role(rawValue: message.role.rawValue) ?? .user,
            content: message.content
        )
    }
}
