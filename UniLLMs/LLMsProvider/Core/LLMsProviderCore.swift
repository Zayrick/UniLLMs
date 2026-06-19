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

nonisolated enum ReasoningEffortConfiguration {
    static let omitValue = -1
    static let disabledValue = 0
}

nonisolated struct LLMsProviderReasoningEffort: Equatable, Hashable {
    var value: Int
    var providerValue: String
    var title: String
}

nonisolated struct LLMsProviderReasoningEffortResolution: Equatable {
    var storedValue: Int
    var resolvedValue: Int
    var providerValue: String?
    var positiveLevelCount: Int
    var activePositiveLevelCount: Int
}

nonisolated struct LLMsProviderReasoningEffortOptions: Equatable {
    var levels: [LLMsProviderReasoningEffort]

    init(levels: [LLMsProviderReasoningEffort] = []) {
        var seenValues = Set<Int>()
        self.levels = levels
            .sorted { $0.value < $1.value }
            .compactMap { level in
                guard level.value >= ReasoningEffortConfiguration.disabledValue,
                      !level.providerValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      seenValues.insert(level.value).inserted else {
                    return nil
                }
                return level
            }
    }

    var positiveLevelCount: Int {
        positiveLevels.count
    }

    func resolution(forStoredValue storedValue: Int) -> LLMsProviderReasoningEffortResolution {
        let resolvedValue: Int
        if storedValue <= ReasoningEffortConfiguration.omitValue {
            resolvedValue = ReasoningEffortConfiguration.omitValue
        } else if storedValue == ReasoningEffortConfiguration.disabledValue {
            resolvedValue = level(forValue: ReasoningEffortConfiguration.disabledValue) == nil
                ? ReasoningEffortConfiguration.omitValue
                : ReasoningEffortConfiguration.disabledValue
        } else {
            resolvedValue = resolvedPositiveValue(for: storedValue)
        }

        let resolvedLevel = level(forValue: resolvedValue)
        return LLMsProviderReasoningEffortResolution(
            storedValue: storedValue,
            resolvedValue: resolvedLevel?.value ?? ReasoningEffortConfiguration.omitValue,
            providerValue: resolvedLevel?.providerValue,
            positiveLevelCount: positiveLevelCount,
            activePositiveLevelCount: activePositiveLevelCount(for: resolvedLevel)
        )
    }

    private var positiveLevels: [LLMsProviderReasoningEffort] {
        levels
            .filter { $0.value > ReasoningEffortConfiguration.disabledValue }
            .sorted { $0.value < $1.value }
    }

    private var positiveValues: [Int] {
        positiveLevels.map(\.value)
    }

    private func resolvedPositiveValue(for storedValue: Int) -> Int {
        let values = positiveValues
        guard !values.isEmpty else {
            return ReasoningEffortConfiguration.omitValue
        }
        if let nearestLowerOrEqual = values.last(where: { $0 <= storedValue }) {
            return nearestLowerOrEqual
        }
        return values[0]
    }

    private func level(forValue value: Int) -> LLMsProviderReasoningEffort? {
        levels.first { $0.value == value }
    }

    private func activePositiveLevelCount(for level: LLMsProviderReasoningEffort?) -> Int {
        guard let level,
              level.value > ReasoningEffortConfiguration.disabledValue,
              let index = positiveLevels.firstIndex(where: { $0.value == level.value }) else {
            return 0
        }

        return index + 1
    }
}

nonisolated struct LLMsProviderModel: Codable, Equatable, Hashable {
    var id: String
    var name: String?
    var contextLength: Int?
    var reasoningEfforts: [String]
    var isReasoningMandatory: Bool

    init(
        id: String,
        name: String? = nil,
        contextLength: Int? = nil,
        reasoningEfforts: [String] = [],
        isReasoningMandatory: Bool = false
    ) {
        self.id = id
        self.name = name
        self.contextLength = contextLength
        self.reasoningEfforts = Self.normalizedReasoningEfforts(reasoningEfforts)
        self.isReasoningMandatory = isReasoningMandatory
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case contextLength
        case reasoningEfforts
        case isReasoningMandatory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
        reasoningEfforts = Self.normalizedReasoningEfforts(
            try container.decodeIfPresent([String].self, forKey: .reasoningEfforts) ?? []
        )
        isReasoningMandatory = try container.decodeIfPresent(Bool.self, forKey: .isReasoningMandatory) ?? false
    }

    private static func normalizedReasoningEfforts(_ efforts: [String]) -> [String] {
        var seen = Set<String>()
        return efforts.compactMap { effort in
            let trimmed = effort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  seen.insert(trimmed.lowercased()).inserted else {
                return nil
            }
            return trimmed
        }
    }
}

nonisolated struct LLMsProviderConfiguration: Codable, Equatable {
    var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    subscript(key: String) -> String {
        get { values[key] ?? "" }
        set { values[key] = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case values
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let values = try container.decodeIfPresent([String: String].self, forKey: .values) {
            self.values = values
            return
        }

        let container = try decoder.container(keyedBy: LLMsProviderDynamicCodingKey.self)
        var decodedValues: [String: String] = [:]
        for key in container.allKeys {
            if let stringValue = try? container.decode(String.self, forKey: key) {
                decodedValues[key.stringValue] = stringValue
            } else if let nestedValues = try? container.decode([String: String].self, forKey: key) {
                nestedValues.forEach { decodedValues[$0.key] = $0.value }
            }
        }
        values = decodedValues
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
    }
}

nonisolated struct LLMsProviderRecord: Codable, Equatable, Identifiable {
    typealias Kind = LLMsProviderKind

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

        return kind.rawValue
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case name
        case configuration
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

        configuration = try container.decodeIfPresent(
            LLMsProviderConfiguration.self,
            forKey: .configuration
        ) ?? Self.decodeLegacyConfigurationValues(from: decoder)
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
    enum Binding: Equatable {
        case providerName
        case configurationValue(String)
    }

    enum InputKind: Equatable {
        case plain
        case secret
        case url
        case toggle
    }

    var id: String
    var title: String
    var placeholder: String
    var binding: Binding
    var inputKind: InputKind
    var isRequired: Bool = false
}

nonisolated extension LLMsProviderRecord {
    func configurationValue(for binding: LLMsProviderConfigurationField.Binding) -> String {
        switch binding {
        case .providerName:
            return name
        case let .configurationValue(key):
            return configuration[key]
        }
    }

    mutating func setConfigurationValue(
        _ value: String,
        for binding: LLMsProviderConfigurationField.Binding
    ) {
        switch binding {
        case .providerName:
            name = value
        case let .configurationValue(key):
            configuration[key] = value
        }
    }

    private static func decodeLegacyConfigurationValues(from decoder: Decoder) throws -> LLMsProviderConfiguration {
        let container = try decoder.container(keyedBy: LLMsProviderDynamicCodingKey.self)
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        var values: [String: String] = [:]

        for key in container.allKeys where !knownKeys.contains(key.stringValue) {
            guard let value = try? container.decode(String.self, forKey: key) else {
                continue
            }

            values[key.stringValue] = value
        }

        return LLMsProviderConfiguration(values: values)
    }
}

nonisolated enum LLMsProviderModelSource: Equatable {
    case remote
    case manual
    case `static`
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
    var modelSource: LLMsProviderModelSource { get }
    var staticModels: [LLMsProviderModel] { get }

    func configurationSummary(for configuration: LLMsProviderConfiguration) -> String?
    func supports(_ capability: LLMsProviderCapability, configuration: LLMsProviderConfiguration) -> Bool
    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws
    func fetchModels(configuration: LLMsProviderConfiguration) async throws -> [LLMsProviderModel]
    func reasoningEffortOptions(for model: LLMsProviderModel) -> LLMsProviderReasoningEffortOptions
    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error>
}

extension LLMsProviderAdapter {
    func configurationSummary(for configuration: LLMsProviderConfiguration) -> String? {
        nil
    }

    func supports(_ capability: LLMsProviderCapability, configuration: LLMsProviderConfiguration) -> Bool {
        capabilities.contains(capability)
    }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {}

    var staticModels: [LLMsProviderModel] {
        []
    }

    func fetchModels(configuration: LLMsProviderConfiguration) async throws -> [LLMsProviderModel] {
        []
    }

    func reasoningEffortOptions(for model: LLMsProviderModel) -> LLMsProviderReasoningEffortOptions {
        LLMsProviderReasoningEffortOptions()
    }
}

final class LLMsProviderRegistry {
    private var adaptersByKind: [LLMsProviderKind: any LLMsProviderAdapter] = [:]
    private var orderedKinds: [LLMsProviderKind] = []

    init(adapters: [any LLMsProviderAdapter] = []) {
        adapters.forEach(register)
    }

    func register(_ adapter: any LLMsProviderAdapter) {
        if adaptersByKind[adapter.kind] == nil {
            orderedKinds.append(adapter.kind)
        }
        adaptersByKind[adapter.kind] = adapter
    }

    func adapter(for kind: LLMsProviderKind) -> (any LLMsProviderAdapter)? {
        adaptersByKind[kind]
    }

    var adapters: [any LLMsProviderAdapter] {
        orderedKinds.compactMap {
            adaptersByKind[$0]
        }
    }
}

enum LLMsProviderManagerError: LocalizedError, Equatable {
    case noRegisteredProviders
    case unsupportedProvider(LLMsProviderKind)

    var errorDescription: String? {
        switch self {
        case .noRegisteredProviders:
            return String(localized: .providersErrorNoRegistered)
        case let .unsupportedProvider(kind):
            return String(localized: .providersErrorUnsupportedFormat(kind.rawValue))
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
        return makeProviderDraft(adapter: adapter)
    }

    func makeDefaultProviderDraft() throws -> LLMsProviderRecord {
        guard let adapter = registry.adapters.first else {
            throw LLMsProviderManagerError.noRegisteredProviders
        }

        return makeProviderDraft(adapter: adapter)
    }

    private func makeProviderDraft(adapter: any LLMsProviderAdapter) -> LLMsProviderRecord {
        let models = adapter.modelSource == .`static` ? adapter.staticModels : []
        return store.makeProviderDraft(
            kind: adapter.kind,
            displayName: adapter.displayName,
            configuration: adapter.defaultConfiguration,
            models: models
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

    func modelSource(for kind: LLMsProviderKind) -> LLMsProviderModelSource? {
        registry.adapter(for: kind)?.modelSource
    }

    func configurationSummary(for provider: LLMsProviderRecord) -> String? {
        registry.adapter(for: provider.kind)?
            .configurationSummary(for: provider.configuration)
    }

    func provider(
        _ provider: LLMsProviderRecord,
        supports capability: LLMsProviderCapability
    ) -> Bool {
        registry.adapter(for: provider.kind)?
            .supports(capability, configuration: provider.configuration) == true
    }

    func fetchSelectedModelSelection() -> ChatModelSelection? {
        store.fetchSelectedModelSelection { provider in
            displayName(for: provider)
        }
    }

    func hasRequiredConfigurationFields(for provider: LLMsProviderRecord) -> Bool {
        configurationFields(for: provider.kind).allSatisfy { field in
            guard field.isRequired else {
                return true
            }

            return !provider.configurationValue(for: field.binding)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    func fetchModels(for provider: LLMsProviderRecord) async throws -> [LLMsProviderModel] {
        let adapter = try requireAdapter(for: provider.kind)
        guard adapter.modelSource != .`static` else {
            return adapter.staticModels
        }

        return try await adapter.fetchModels(configuration: provider.configuration)
    }

    func reasoningEffortOptions(
        for provider: LLMsProviderRecord,
        model: LLMsProviderModel
    ) -> LLMsProviderReasoningEffortOptions {
        registry.adapter(for: provider.kind)?.reasoningEffortOptions(for: model)
            ?? LLMsProviderReasoningEffortOptions()
    }

    func streamChat(
        provider: LLMsProviderRecord,
        modelID: String,
        messages: [ChatMessage],
        context: ChatContext,
        reasoningEffort: String? = nil
    ) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
        let adapter = try requireAdapter(for: provider.kind)
        try adapter.validateChatConfiguration(provider.configuration)
        return adapter.streamChat(
            request: ChatRequest(
                modelID: modelID,
                messages: messages,
                context: context,
                reasoningEffort: reasoningEffort
            ),
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

private struct LLMsProviderDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
