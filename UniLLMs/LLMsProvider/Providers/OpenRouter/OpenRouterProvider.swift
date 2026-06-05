//
//  OpenRouterProvider.swift
//  UniLLMs
//
//  OpenRouter provider adapter.
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
            return LLMsProviderStreamSupport.failedChatResponseStream(error)
        }

        let tools = request.context.availableTools.map(OpenRouterChatTool.init(definition:))
        let stream = apiClient.streamChatCompletion(
            apiBase: configuration[ConfigurationKey.apiBase],
            apiKey: configuration[ConfigurationKey.apiKey],
            model: request.modelID,
            messages: messages,
            tools: tools,
            sessionID: request.providerContext.sessionIdentifier?.value(maxLength: 256)
        )

        return LLMsProviderStreamSupport.chatResponseStream(from: stream)
    }
}

enum OpenRouterProviderError: LocalizedError, Equatable {
    case missingAPIKey(String)
    case unsupportedFileAttachments(String)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(displayName):
            return String(localized: .providersErrorMissingApiKeyFormat(displayName))
        case let .unsupportedFileAttachments(displayName):
            return String(localized: .providersErrorUnsupportedFileAttachmentsFormat(displayName))
        }
    }
}

nonisolated enum OpenRouterChatPromptRenderer {
    static func messages(
        for request: ChatRequest,
        supportsFileAttachments: Bool,
        attachmentPayloadLoader: LLMsProviderAttachmentPayloadLoader = .shared
    ) throws -> [OpenRouterChatMessage] {
        try OpenAICompatibleChatPromptRenderer.messages(
            for: request,
            options: OpenAICompatibleChatPromptRenderingOptions(
                instructionRole: .system,
                supportsFileAttachments: supportsFileAttachments,
                serviceName: "OpenRouter",
                attachmentPayloadLoader: attachmentPayloadLoader
            )
        )
    }
}
