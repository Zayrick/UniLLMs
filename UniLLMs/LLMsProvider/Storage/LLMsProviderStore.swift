//
//  LLMsProviderStore.swift
//  UniLLMs
//
//  Created by Zayrick configuration, model cache, and selected model with UserDefaults while migrating legacy configuration fields.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class LLMsProviderStore {
    static let shared = LLMsProviderStore()
    static let selectedModelSelectionDidChangeNotification = Notification.Name(
        "LLMsProviderStoreSelectedModelSelectionDidChange"
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

    func fetchProviders() -> [LLMsProviderRecord] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        return (try? decoder.decode([LLMsProviderRecord].self, from: data)) ?? []
    }

    func fetchProvider(id: UUID) -> LLMsProviderRecord? {
        fetchProviders().first { $0.id == id }
    }

    func makeProviderDraft(
        kind: LLMsProviderKind,
        displayName: String,
        configuration: LLMsProviderConfiguration
    ) -> LLMsProviderRecord {
        let providers = fetchProviders()
        return LLMsProviderRecord(
            id: UUID(),
            kind: kind,
            name: makeUniqueProviderName(
                baseName: displayName,
                existingProviders: providers
            ),
            configuration: configuration,
            models: [],
            modelsUpdatedAt: nil,
            createdAt: Date()
        )
    }

    func saveProvider(_ provider: LLMsProviderRecord) {
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

    func updateProvider(_ provider: LLMsProviderRecord) {
        saveProvider(provider)
    }

    func updateProviderModels(
        id: UUID,
        models: [LLMsProviderModel],
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

    func fetchSelectedModelSelection(
        providerDisplayName: (LLMsProviderRecord) -> String = { $0.displayName }
    ) -> ChatModelSelection? {
        guard let persistedSelection = fetchPersistedModelSelection() else {
            return nil
        }

        let providers = fetchProviders()
        guard let selection = resolvedModelSelection(
            for: persistedSelection,
            providers: providers,
            providerDisplayName: providerDisplayName
        ) else {
            clearSelectedModelSelection()
            return nil
        }

        return selection
    }

    func saveSelectedModelSelection(_ selection: ChatModelSelection) {
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

    private func save(_ providers: [LLMsProviderRecord]) {
        guard let data = try? encoder.encode(providers) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    private func makeUniqueProviderName(
        baseName: String,
        existingProviders: [LLMsProviderRecord]
    ) -> String {
        let existingNames = Set(existingProviders.map(\.name))

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
        providers: [LLMsProviderRecord],
        providerDisplayName: (LLMsProviderRecord) -> String
    ) -> ChatModelSelection? {
        guard let provider = providers.first(where: { $0.id == persistedSelection.providerID }),
              let model = provider.models.first(where: { $0.id == persistedSelection.modelID }) else {
            return nil
        }

        return ChatModelSelection(
            providerID: provider.id,
            providerName: providerDisplayName(provider),
            modelID: model.id,
            modelName: model.name
        )
    }

    private func reconcileSelectedModelSelection(
        afterChangingProviderID changedProviderID: UUID,
        providers: [LLMsProviderRecord]
    ) {
        guard let persistedSelection = fetchPersistedModelSelection(),
              persistedSelection.providerID == changedProviderID else {
            return
        }

        guard resolvedModelSelection(
            for: persistedSelection,
            providers: providers,
            providerDisplayName: { $0.displayName }
        ) != nil else {
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
}
