//
//  LLMsProviderCore.swift
//  UniLLMs
//
//  Created by Zayrickder kinds, configuration, capabilities, adapters, registry, and manager as the open-closed extension boundary for new providers.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct LLMsProviderKind: RawRepresentable, Codable, Hashable, Equatable, ExpressibleByStringLiteral {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated extension LLMsProviderKind {
    static let openRouter = LLMsProviderKind(rawValue: "openRouter")
}

nonisolated struct LLMsProviderModel: Codable, Equatable, Hashable {
    var id: String
    var name: String
    var contextLength: Int?
}

nonisolated struct LLMsProviderConfiguration: Codable, Equatable {
    var apiKey: String
    var apiBase: String
    var extra: [String: String]

    init(apiKey: String = "", apiBase: String = "", extra: [String: String] = [:]) {
        self.apiKey = apiKey
        self.apiBase = apiBase
        self.extra = extra
    }
}

nonisolated struct LLMsProviderRecord: Codable, Equatable, Identifiable {
    typealias Kind = LLMsProviderKind

    static let openRouterDisplayName = "OpenRouter"
    static let openRouterDefaultAPIBase = "https://openrouter.ai/api/v1"

    var id: UUID
    var kind: LLMsProviderKind
    var name: String
    var configuration: LLMsProviderConfiguration
    var models: [LLMsProviderModel]
    var modelsUpdatedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: LLMsProviderKind,
        name: String,
        configuration: LLMsProviderConfiguration,
        models: [LLMsProviderModel] = [],
        modelsUpdatedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.configuration = configuration
        self.models = models
        self.modelsUpdatedAt = modelsUpdatedAt
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty else {
            return trimmedName
        }

        return kind == .openRouter ? Self.openRouterDisplayName : kind.rawValue
    }

    var apiKey: String {
        get { configuration.apiKey }
        set { configuration.apiKey = newValue }
    }

    var apiBase: String {
        get { configuration.apiBase }
        set { configuration.apiBase = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case configuration
        case apiKey
        case apiBase
        case models
        case modelsUpdatedAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(LLMsProviderKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        models = try container.decodeIfPresent([LLMsProviderModel].self, forKey: .models) ?? []
        modelsUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .modelsUpdatedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        if let configuration = try container.decodeIfPresent(
            LLMsProviderConfiguration.self,
            forKey: .configuration
        ) {
            self.configuration = configuration
        } else {
            self.configuration = LLMsProviderConfiguration(
                apiKey: try container.decodeIfPresent(String.self, forKey: .apiKey) ?? "",
                apiBase: try container.decodeIfPresent(String.self, forKey: .apiBase)
                    ?? Self.openRouterDefaultAPIBase
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(models, forKey: .models)
        try container.encodeIfPresent(modelsUpdatedAt, forKey: .modelsUpdatedAt)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

nonisolated struct LLMsProviderConfigurationField: Equatable, Identifiable {
    enum ValueKey: Equatable {
        case providerName
        case apiKey
        case apiBase
        case extra(String)
    }

    enum InputKind: Equatable {
        case plain
        case secret
        case url
    }

    var id: String
    var title: String
    var placeholder: String
    var valueKey: ValueKey
    var inputKind: InputKind
}

nonisolated enum LLMsProviderCapability: String, Codable, Hashable {
    case modelList
    case streamingChat
    case nonStreamingChat
    case tools
}

protocol LLMsProviderAdapter {
    var kind: LLMsProviderKind { get }
    var displayName: String { get }
    var capabilities: Set<LLMsProviderCapability> { get }
    var defaultConfiguration: LLMsProviderConfiguration { get }
    var configurationFields: [LLMsProviderConfigurationField] { get }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws
    func fetchModels(configuration: LLMsProviderConfiguration) async throws -> [LLMsProviderModel]
    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error>
}

extension LLMsProviderAdapter {
    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {}
}

final class LLMsProviderRegistry {
    private var adaptersByKind: [LLMsProviderKind: any LLMsProviderAdapter] = [:]

    init(adapters: [any LLMsProviderAdapter] = []) {
        adapters.forEach(register)
    }

    func register(_ adapter: any LLMsProviderAdapter) {
        adaptersByKind[adapter.kind] = adapter
    }

    func adapter(for kind: LLMsProviderKind) -> (any LLMsProviderAdapter)? {
        adaptersByKind[kind]
    }

    var adapters: [any LLMsProviderAdapter] {
        adaptersByKind.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

enum LLMsProviderManagerError: LocalizedError, Equatable {
    case unsupportedProvider(LLMsProviderKind)

    var errorDescription: String? {
        switch self {
        case let .unsupportedProvider(kind):
            return "Unsupported LLM provider: \(kind.rawValue)"
        }
    }
}

final class LLMsProviderManager {
    let registry: LLMsProviderRegistry
    let store: LLMsProviderStore

    init(registry: LLMsProviderRegistry, store: LLMsProviderStore) {
        self.registry = registry
        self.store = store
    }

    func makeProviderDraft(kind: LLMsProviderKind) throws -> LLMsProviderRecord {
        let adapter = try requireAdapter(for: kind)
        return store.makeProviderDraft(
            kind: adapter.kind,
            displayName: adapter.displayName,
            configuration: adapter.defaultConfiguration
        )
    }

    @discardableResult
    func addProvider(kind: LLMsProviderKind) throws -> LLMsProviderRecord {
        let provider = try makeProviderDraft(kind: kind)
        store.saveProvider(provider)
        return provider
    }

    func displayName(for provider: LLMsProviderRecord) -> String {
        let trimmedName = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty else {
            return trimmedName
        }

        return registry.adapter(for: provider.kind)?.displayName ?? provider.displayName
    }

    func configurationFields(for kind: LLMsProviderKind) -> [LLMsProviderConfigurationField] {
        registry.adapter(for: kind)?.configurationFields ?? []
    }

    func fetchModels(for provider: LLMsProviderRecord) async throws -> [LLMsProviderModel] {
        try await requireAdapter(for: provider.kind)
            .fetchModels(configuration: provider.configuration)
    }

    func streamChatCompletion(
        provider: LLMsProviderRecord,
        modelID: String,
        messages: [ChatMessage],
        context: ChatContext
    ) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
        let adapter = try requireAdapter(for: provider.kind)
        try adapter.validateChatConfiguration(provider.configuration)
        return adapter.streamChat(
            request: ChatRequest(modelID: modelID, messages: messages, context: context),
            configuration: provider.configuration
        )
    }

    private func requireAdapter(for kind: LLMsProviderKind) throws -> any LLMsProviderAdapter {
        guard let adapter = registry.adapter(for: kind) else {
            throw LLMsProviderManagerError.unsupportedProvider(kind)
        }

        return adapter
    }
}

typealias LLMProviderModel = LLMsProviderModel
typealias LLMProviderRecord = LLMsProviderRecord
typealias LLMProviderStore = LLMsProviderStore
