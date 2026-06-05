//
//  OpenAIProvider.swift
//  UniLLMs
//
//  Native OpenAI provider adapter.
//  Created by Codex on 2026/5/22.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let openAI = LLMsProviderKind(rawValue: "openAI")
}

struct OpenAIProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "OpenAI"
        static let defaultAPIBase = "https://api.openai.com/v1"
    }

    enum ConfigurationKey {
        static let apiKey = "apiKey"
        static let apiBase = "apiBase"
    }

    let apiClient: OpenAIAPIClient

    init(
        apiClient: OpenAIAPIClient = OpenAIAPIClient()
    ) {
        self.apiClient = apiClient
    }

    var kind: LLMsProviderKind {
        .openAI
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
            throw OpenAIProviderError.missingAPIKey(displayName)
        }
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        guard !LLMsProviderStreamSupport.containsFileAttachments(request) else {
            return LLMsProviderStreamSupport.failedChatResponseStream(
                OpenAIProviderError.unsupportedFileAttachments(displayName)
            )
        }

        let messages: [OpenAIChatMessage]
        do {
            messages = try OpenAIChatPromptRenderer.messages(
                for: request,
                instructionRole: .system
            )
        } catch {
            return LLMsProviderStreamSupport.failedChatResponseStream(error)
        }
        let tools = request.context.availableTools.map(OpenAIChatTool.init(definition:))
        let stream = apiClient.streamChatCompletion(
            apiBase: configuration[ConfigurationKey.apiBase],
            apiKey: configuration[ConfigurationKey.apiKey],
            model: request.modelID,
            messages: messages,
            tools: tools
        )

        return LLMsProviderStreamSupport.chatResponseStream(from: stream)
    }
}

enum OpenAIProviderError: LocalizedError, Equatable {
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

nonisolated enum OpenAIChatPromptRenderer {
    nonisolated enum InstructionRole {
        case system
        case developer
    }

    static func messages(
        for request: ChatRequest,
        instructionRole: InstructionRole = .system,
        attachmentPayloadLoader: LLMsProviderAttachmentPayloadLoader = .shared
    ) throws -> [OpenAIChatMessage] {
        let role: OpenAIChatMessage.Role
        switch instructionRole {
        case .system:
            role = .system
        case .developer:
            role = .developer
        }

        return try OpenAICompatibleChatPromptRenderer.messages(
            for: request,
            options: OpenAICompatibleChatPromptRenderingOptions(
                instructionRole: role,
                supportsFileAttachments: false,
                serviceName: "OpenAI",
                attachmentPayloadLoader: attachmentPayloadLoader
            )
        )
    }
}

typealias OpenAIMessageContent = OpenAICompatibleMessageContent
typealias OpenAIContentPart = OpenAICompatibleContentPart
typealias OpenAIChatMessage = OpenAICompatibleChatMessage
typealias OpenAIChatTool = OpenAICompatibleChatTool
typealias OpenAIToolCallDelta = OpenAICompatibleToolCallDelta
typealias OpenAIChatStreamDelta = OpenAICompatibleChatStreamDelta

nonisolated struct OpenAIAPIClient {
    typealias APIError = OpenAICompatibleAPIClient.APIError

    private var client: OpenAICompatibleAPIClient

    var session: URLSession {
        get {
            client.session
        }
        set {
            client.session = newValue
        }
    }

    var serviceName: String {
        get {
            client.serviceName
        }
        set {
            client.serviceName = newValue
        }
    }

    var defaultAPIBase: String {
        get {
            client.defaultAPIBase
        }
        set {
            client.defaultAPIBase = newValue
        }
    }

    init(
        session: URLSession = .shared,
        serviceName: String = "OpenAI",
        defaultAPIBase: String = "https://api.openai.com/v1"
    ) {
        client = OpenAICompatibleAPIClient(
            session: session,
            serviceName: serviceName,
            defaultAPIBase: defaultAPIBase
        )
    }

    func fetchModels(apiBase: String, apiKey: String) async throws -> [LLMsProviderModel] {
        try await client.fetchModels(
            apiBase: apiBase,
            apiKey: apiKey,
            includeModelMetadata: false,
            authorizationPolicy: .includeBearerEvenWhenBlank
        )
    }

    func streamChatCompletion(
        apiBase: String,
        apiKey: String,
        model: String,
        messages: [OpenAIChatMessage],
        tools: [OpenAIChatTool] = []
    ) -> AsyncThrowingStream<OpenAIChatStreamDelta, Error> {
        client.streamChatCompletion(
            apiBase: apiBase,
            apiKey: apiKey,
            model: model,
            messages: messages,
            tools: tools,
            authorizationPolicy: .includeBearerEvenWhenBlank,
            includesReasoningDetails: false,
            fallbackToolCallIDPrefix: "openai_tool_call_"
        )
    }

    nonisolated static func streamDelta(
        fromServerSentEventLine line: String,
        serviceName: String = "OpenAI"
    ) throws -> OpenAIChatStreamDelta? {
        try OpenAICompatibleAPIClient.streamDelta(
            fromServerSentEventLine: line,
            serviceName: serviceName,
            includesReasoningDetails: false
        )
    }
}
