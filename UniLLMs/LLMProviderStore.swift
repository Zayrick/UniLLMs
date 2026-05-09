//
//  LLMProviderStore.swift
//  UniLLMs
//
//  Created by OpenAI on 2026/5/10.
//

import Foundation

struct LLMProviderModel: Codable, Equatable, Hashable {
    var id: String
    var name: String
    var contextLength: Int?
}

struct LLMProviderRecord: Codable, Equatable, Identifiable {
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

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "llmProviderConfigurations.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func fetchProviders() -> [LLMProviderRecord] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        return (try? decoder.decode([LLMProviderRecord].self, from: data)) ?? []
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
    }

    func deleteProvider(id: UUID) {
        var providers = fetchProviders()
        providers.removeAll { $0.id == id }
        save(providers)
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
}
