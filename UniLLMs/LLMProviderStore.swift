//
//  LLMProviderStore.swift
//  UniLLMs
//
//  Created by OpenAI on 2026/5/10.
//

import Foundation

nonisolated struct LLMModelSelection: Equatable {
    var providerID: UUID
    var providerName: String
    var modelID: String
    var modelName: String

    var displayName: String {
        modelName.isEmpty ? modelID : modelName
    }
}

nonisolated struct LLMProviderModel: Codable, Equatable, Hashable {
    var id: String
    var name: String
    var contextLength: Int?
}

nonisolated struct LLMProviderRecord: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case openRouter
    }

    static let openRouterDisplayName = "OpenRouter"
    static let openRouterDefaultAPIBase = "https://openrouter.ai/api/v1"

    var id: UUID
    var kind: Kind
    var name: String
    var apiKey: String
    var apiBase: String
    var models: [LLMProviderModel]
    var modelsUpdatedAt: Date?
    var createdAt: Date
}

final class LLMProviderStore {
    static let shared = LLMProviderStore()
    static let selectedModelSelectionDidChangeNotification = Notification.Name(
        "LLMProviderStoreSelectedModelSelectionDidChange"
    )

    private struct PersistedModelSelection: Codable, Equatable {
        var providerID: UUID
        var modelID: String
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let selectedModelStorageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "llmProviderConfigurations.v1",
        selectedModelStorageKey: String = "selectedLLMModel.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.selectedModelStorageKey = selectedModelStorageKey
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func fetchProviders() -> [LLMProviderRecord] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        return (try? decoder.decode([LLMProviderRecord].self, from: data)) ?? []
    }

    func fetchProvider(id: UUID) -> LLMProviderRecord? {
        fetchProviders().first { $0.id == id }
    }

    func makeOpenRouterProviderDraft() -> LLMProviderRecord {
        let providers = fetchProviders()
        return LLMProviderRecord(
            id: UUID(),
            kind: .openRouter,
            name: makeUniqueOpenRouterName(existingProviders: providers),
            apiKey: "",
            apiBase: LLMProviderRecord.openRouterDefaultAPIBase,
            models: [],
            modelsUpdatedAt: nil,
            createdAt: Date()
        )
    }

    @discardableResult
    func addOpenRouterProvider() -> LLMProviderRecord {
        let provider = makeOpenRouterProviderDraft()
        saveProvider(provider)
        return provider
    }

    func saveProvider(_ provider: LLMProviderRecord) {
        var providers = fetchProviders()
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        save(providers)
        reconcileSelectedModelSelection(
            afterChangingProviderID: provider.id,
            providers: providers
        )
    }

    func updateProvider(_ provider: LLMProviderRecord) {
        saveProvider(provider)
    }

    func updateProviderModels(
        id: UUID,
        models: [LLMProviderModel],
        modelsUpdatedAt: Date
    ) {
        var providers = fetchProviders()
        guard let index = providers.firstIndex(where: { $0.id == id }) else {
            return
        }

        providers[index].models = models
        providers[index].modelsUpdatedAt = modelsUpdatedAt
        save(providers)
        reconcileSelectedModelSelection(
            afterChangingProviderID: id,
            providers: providers
        )
    }

    func deleteProvider(id: UUID) {
        var providers = fetchProviders()
        providers.removeAll { $0.id == id }
        save(providers)
        reconcileSelectedModelSelection(
            afterChangingProviderID: id,
            providers: providers
        )
    }

    func fetchSelectedModelSelection() -> LLMModelSelection? {
        guard let persistedSelection = fetchPersistedModelSelection() else {
            return nil
        }

        let providers = fetchProviders()
        guard let selection = resolvedModelSelection(
            for: persistedSelection,
            providers: providers
        ) else {
            clearSelectedModelSelection()
            return nil
        }

        return selection
    }

    func saveSelectedModelSelection(_ selection: LLMModelSelection) {
        let persistedSelection = PersistedModelSelection(
            providerID: selection.providerID,
            modelID: selection.modelID
        )
        guard let data = try? encoder.encode(persistedSelection) else {
            return
        }

        defaults.set(data, forKey: selectedModelStorageKey)
        notifySelectedModelSelectionDidChange()
    }

    func clearSelectedModelSelection() {
        guard defaults.object(forKey: selectedModelStorageKey) != nil else {
            return
        }

        defaults.removeObject(forKey: selectedModelStorageKey)
        notifySelectedModelSelectionDidChange()
    }

    private func save(_ providers: [LLMProviderRecord]) {
        guard let data = try? encoder.encode(providers) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    private func makeUniqueOpenRouterName(existingProviders: [LLMProviderRecord]) -> String {
        let existingNames = Set(existingProviders.map(\.name))
        let baseName = LLMProviderRecord.openRouterDisplayName

        guard existingNames.contains(baseName) else {
            return baseName
        }

        var suffix = 1
        while existingNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }

        return "\(baseName) \(suffix)"
    }

    private func fetchPersistedModelSelection() -> PersistedModelSelection? {
        guard let data = defaults.data(forKey: selectedModelStorageKey) else {
            return nil
        }

        return try? decoder.decode(PersistedModelSelection.self, from: data)
    }

    private func resolvedModelSelection(
        for persistedSelection: PersistedModelSelection,
        providers: [LLMProviderRecord]
    ) -> LLMModelSelection? {
        guard let provider = providers.first(where: { $0.id == persistedSelection.providerID }),
              let model = provider.models.first(where: { $0.id == persistedSelection.modelID }) else {
            return nil
        }

        return LLMModelSelection(
            providerID: provider.id,
            providerName: providerDisplayName(provider),
            modelID: model.id,
            modelName: model.name
        )
    }

    private func reconcileSelectedModelSelection(
        afterChangingProviderID changedProviderID: UUID,
        providers: [LLMProviderRecord]
    ) {
        guard let persistedSelection = fetchPersistedModelSelection(),
              persistedSelection.providerID == changedProviderID else {
            return
        }

        guard resolvedModelSelection(for: persistedSelection, providers: providers) != nil else {
            clearSelectedModelSelection()
            return
        }

        notifySelectedModelSelectionDidChange()
    }

    private func notifySelectedModelSelectionDidChange() {
        NotificationCenter.default.post(
            name: Self.selectedModelSelectionDidChangeNotification,
            object: self
        )
    }

    private func providerDisplayName(_ provider: LLMProviderRecord) -> String {
        let trimmedName = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? LLMProviderRecord.openRouterDisplayName : trimmedName
    }
}
