//
//  OpenAICompatibleProvider.swift
//  UniLLMs
//
//  Adds OpenAI-compatible streaming chat providers with user-managed model IDs.
//  Created by Zayrick on 2026/5/12.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let openAICompatible = LLMsProviderKind(rawValue: "openAICompatible")
}

struct OpenAICompatibleProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "OpenAI Compatible"
    }

    enum ConfigurationKey {
        static let apiBase = "apiBase"
        static let apiKey = "apiKey"
        static let toolsEnabled = "toolsEnabled"
    }

    let apiClient: OpenRouterAPIClient

    init(
        apiClient: OpenRouterAPIClient = OpenRouterAPIClient(
            serviceName: Metadata.displayName,
            defaultAPIBase: ""
        )
    ) {
        self.apiClient = apiClient
    }

    var kind: LLMsProviderKind {
        .openAICompatible
    }

    var displayName: String {
        Metadata.displayName
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.streamingChat]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration(
            values: [
                ConfigurationKey.apiBase: "",
                ConfigurationKey.apiKey: "",
                ConfigurationKey.toolsEnabled: "false"
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
                id: ConfigurationKey.apiBase,
                title: "API Base",
                placeholder: "https://api.openai.com/v1",
                binding: .configurationValue(ConfigurationKey.apiBase),
                inputKind: .url,
                isRequired: true
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.apiKey,
                title: "Key",
                placeholder: "OpenAI API Key",
                binding: .configurationValue(ConfigurationKey.apiKey),
                inputKind: .secret
            ),
            LLMsProviderConfigurationField(
                id: ConfigurationKey.toolsEnabled,
                title: "Tools",
                placeholder: "",
                binding: .configurationValue(ConfigurationKey.toolsEnabled),
                inputKind: .toggle
            )
        ]
    }

    var modelSource: LLMsProviderModelSource {
        .manual
    }

    func configurationSummary(for configuration: LLMsProviderConfiguration) -> String? {
        configuration[ConfigurationKey.apiBase]
    }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {
        guard !configuration[ConfigurationKey.apiBase].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleProviderError.missingAPIBase(displayName)
        }
    }

    func supports(
        _ capability: LLMsProviderCapability,
        configuration: LLMsProviderConfiguration
    ) -> Bool {
        switch capability {
        case .tools:
            return Self.isToolsEnabled(configuration)
        default:
            return capabilities.contains(capability)
        }
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        let messages = request.messages.map(OpenRouterChatMessage.init(message:))
        let tools = Self.isToolsEnabled(configuration)
            ? request.context.availableTools.map(OpenRouterChatTool.init(definition:))
            : []
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

    private static func isToolsEnabled(_ configuration: LLMsProviderConfiguration) -> Bool {
        let value = configuration[ConfigurationKey.toolsEnabled]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["true", "1", "yes", "on"].contains(value)
    }
}

enum OpenAICompatibleProviderError: LocalizedError, Equatable {
    case missingAPIBase(String)

    var errorDescription: String? {
        switch self {
        case let .missingAPIBase(displayName):
            return "Add an API base for \(displayName) in Settings first."
        }
    }
}
