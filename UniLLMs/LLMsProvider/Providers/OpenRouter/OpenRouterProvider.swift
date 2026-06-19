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

    private enum ReasoningEffortValue {
        static let minimal = 1
        static let low = 2
        static let medium = 3
        static let high = 4
        static let xhigh = 5
        static let max = 6
        static let unknownStart = 100
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

    func reasoningEffortOptions(for model: LLMsProviderModel) -> LLMsProviderReasoningEffortOptions {
        Self.reasoningEffortOptions(
            from: model.reasoningEfforts,
            allowsDisabledReasoning: !model.isReasoningMandatory
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
                        sessionID: request.providerContext.sessionIdentifier?.value(maxLength: 256),
                        reasoningEffort: request.reasoningEffort
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

    private static func reasoningEffortOptions(
        from efforts: [String],
        allowsDisabledReasoning: Bool
    ) -> LLMsProviderReasoningEffortOptions {
        var seen = Set<String>()
        var positiveTitleLevel = 1
        let levels = sortedReasoningEfforts(efforts).compactMap { effort -> LLMsProviderReasoningEffort? in
            let trimmed = effort.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty,
                  seen.insert(key).inserted else {
                return nil
            }

            if key == "none" {
                guard allowsDisabledReasoning else {
                    return nil
                }

                return LLMsProviderReasoningEffort(
                    value: ReasoningEffortConfiguration.disabledValue,
                    providerValue: trimmed,
                    title: String(localized: .composerReasoningEffortNone)
                )
            }

            let fallbackTitleLevel = positiveTitleLevel
            let value = reasoningEffortConfigurationValue(for: key, fallbackLevel: fallbackTitleLevel)
            defer {
                positiveTitleLevel += 1
            }
            return LLMsProviderReasoningEffort(
                value: value,
                providerValue: trimmed,
                title: localizedReasoningEffortTitle(trimmed, fallbackValue: fallbackTitleLevel)
            )
        }
        return LLMsProviderReasoningEffortOptions(levels: levels)
    }

    private static func sortedReasoningEfforts(_ efforts: [String]) -> [String] {
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
        let orderByEffort = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return efforts.enumerated().sorted { lhs, rhs in
            let lhsKey = lhs.element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rhsKey = rhs.element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch (orderByEffort[lhsKey], orderByEffort[rhsKey]) {
            case let (lhsOrder?, rhsOrder?):
                return lhsOrder == rhsOrder ? lhs.offset < rhs.offset : lhsOrder < rhsOrder
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func reasoningEffortConfigurationValue(for key: String, fallbackLevel: Int) -> Int {
        switch key {
        case "minimal":
            return ReasoningEffortValue.minimal
        case "low":
            return ReasoningEffortValue.low
        case "medium":
            return ReasoningEffortValue.medium
        case "high":
            return ReasoningEffortValue.high
        case "xhigh":
            return ReasoningEffortValue.xhigh
        case "max":
            return ReasoningEffortValue.max
        default:
            return ReasoningEffortValue.unknownStart + fallbackLevel
        }
    }

    private static func localizedReasoningEffortTitle(_ effort: String, fallbackValue: Int) -> String {
        switch effort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "minimal":
            return String(localized: .composerReasoningEffortMinimal)
        case "low":
            return String(localized: .composerReasoningEffortLow)
        case "medium":
            return String(localized: .composerReasoningEffortMedium)
        case "high":
            return String(localized: .composerReasoningEffortHigh)
        case "xhigh":
            return String(localized: .composerReasoningEffortXhigh)
        case "max":
            return String(localized: .composerReasoningEffortMax)
        case "auto":
            return String(localized: .composerReasoningEffortAuto)
        case "default":
            return String(localized: .composerReasoningEffortDefault)
        default:
            return String(localized: .composerReasoningEffortLevelFormat(fallbackValue))
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
        try OpenAICompatibleChatPromptRenderer.messages(
            for: request,
            options: OpenAICompatibleChatPromptRenderingOptions(
                instructionRole: .system,
                supportsFileAttachments: supportsFileAttachments,
                serviceName: "OpenRouter"
            )
        )
    }
}
