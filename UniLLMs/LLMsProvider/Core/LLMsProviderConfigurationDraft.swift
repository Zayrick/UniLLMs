//
//  LLMsProviderConfigurationDraft.swift
//  UniLLMs
//
//  Holds the editable provider configuration state used by the settings UI.
//

import Foundation

nonisolated struct LLMsProviderConfigurationDraft {
    private(set) var provider: LLMsProviderRecord
    private(set) var savedProvider: LLMsProviderRecord
    let modelSource: LLMsProviderModelSource?

    init(
        provider: LLMsProviderRecord,
        savedProvider: LLMsProviderRecord? = nil,
        modelSource: LLMsProviderModelSource?
    ) {
        self.provider = provider
        self.savedProvider = savedProvider ?? provider
        self.modelSource = modelSource
    }

    var manualModelCount: Int {
        provider.models
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    var hasUnsavedChanges: Bool {
        providerForComparison(provider) != providerForComparison(savedProvider)
    }

    func canSave(
        isNewProvider: Bool,
        hasRequiredConfigurationFields: Bool
    ) -> Bool {
        hasRequiredConfigurationFields && (isNewProvider || hasUnsavedChanges)
    }

    func value(for field: LLMsProviderConfigurationField) -> String {
        provider.configurationValue(for: field.binding)
    }

    func booleanValue(for field: LLMsProviderConfigurationField) -> Bool {
        let normalizedValue = value(for: field)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["true", "1", "yes", "on"].contains(normalizedValue)
    }

    mutating func setValue(
        _ text: String,
        for field: LLMsProviderConfigurationField
    ) {
        provider.setConfigurationValue(text, for: field.binding)
    }

    @discardableResult
    mutating func appendManualModel() -> Int {
        provider.models.append(
            LLMsProviderModel(
                id: "",
                name: nil,
                contextLength: nil
            )
        )
        return provider.models.count - 1
    }

    @discardableResult
    mutating func removeManualModel(at modelIndex: Int) -> Bool {
        guard provider.models.indices.contains(modelIndex) else {
            return false
        }

        provider.models.remove(at: modelIndex)
        return true
    }

    @discardableResult
    mutating func setManualModelID(
        _ text: String,
        at modelIndex: Int
    ) -> Bool {
        guard provider.models.indices.contains(modelIndex) else {
            return false
        }

        provider.models[modelIndex].id = text
        provider.models[modelIndex].name = Self.normalizedModelName(provider.models[modelIndex].name)
        return true
    }

    mutating func replaceRemoteModels(
        _ models: [LLMsProviderModel],
        updatedAt: Date
    ) {
        provider.models = models
        provider.modelsUpdatedAt = updatedAt
        savedProvider.models = models
        savedProvider.modelsUpdatedAt = updatedAt
    }

    mutating func markSaved(_ savedProvider: LLMsProviderRecord) {
        let normalizedProvider = Self.normalizedProvider(savedProvider)
        provider = normalizedProvider
        self.savedProvider = normalizedProvider
    }

    func providerForSaving(updatedAt: Date) -> LLMsProviderRecord {
        var normalizedRecord = Self.normalizedProvider(provider)
        guard hasManualModelListChanges else {
            return normalizedRecord
        }

        normalizedRecord.modelsUpdatedAt = updatedAt
        return normalizedRecord
    }

    func modelTitle(for model: LLMsProviderModel) -> String {
        Self.normalizedModelName(model.name) ?? model.id
    }

    func modelSubtitle(for model: LLMsProviderModel) -> String? {
        Self.normalizedModelName(model.name) == nil ? nil : model.id
    }

    static func normalizedProvider(_ provider: LLMsProviderRecord) -> LLMsProviderRecord {
        var normalizedRecord = provider
        normalizedRecord.models = provider.models.compactMap { model in
            let trimmedID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                return nil
            }

            return LLMsProviderModel(
                id: trimmedID,
                name: normalizedModelName(model.name),
                contextLength: model.contextLength
            )
        }
        return normalizedRecord
    }

    static func normalizedModelName(_ name: String?) -> String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func providerForComparison(_ provider: LLMsProviderRecord) -> LLMsProviderRecord {
        var normalizedRecord = Self.normalizedProvider(provider)
        if modelSource == .manual {
            normalizedRecord.modelsUpdatedAt = Self.normalizedProvider(savedProvider).modelsUpdatedAt
        }
        return normalizedRecord
    }

    private var hasManualModelListChanges: Bool {
        guard modelSource == .manual else {
            return false
        }

        return Self.normalizedProvider(provider).models != Self.normalizedProvider(savedProvider).models
    }
}
