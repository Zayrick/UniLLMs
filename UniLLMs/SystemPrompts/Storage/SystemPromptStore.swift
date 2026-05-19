//
//  SystemPromptStore.swift
//  UniLLMs
//
//  Persists user-created system prompt records.
//  Created by Codex on 2026/5/19.
//

import Foundation

protocol SystemPromptStore {
    func loadPrompts() -> [SystemPromptRecord]
    func savePromptRecord(_ prompt: SystemPromptRecord)
    func deletePromptRecord(id: UUID)
}

final class UserDefaultsSystemPromptStore: SystemPromptStore {
    static let shared = UserDefaultsSystemPromptStore()
    static let didChangeNotification = Notification.Name("UserDefaultsSystemPromptStoreDidChange")

    private struct PersistedState: Codable, Equatable {
        var prompts: [SystemPromptRecord]

        init(prompts: [SystemPromptRecord] = []) {
            self.prompts = prompts
        }

        private enum CodingKeys: String, CodingKey {
            case prompts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            prompts = try container.decodeIfPresent([SystemPromptRecord].self, forKey: .prompts) ?? []
        }
    }

    private let store: UserDefaultsStore
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "systemPromptConfigurations.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults)
        self.storageKey = storageKey
    }

    func loadPrompts() -> [SystemPromptRecord] {
        loadState().prompts
    }

    func savePromptRecord(_ prompt: SystemPromptRecord) {
        var state = loadState()
        if let index = state.prompts.firstIndex(where: { $0.id == prompt.id }) {
            state.prompts[index] = prompt
        } else {
            state.prompts.append(prompt)
        }
        saveState(state)
    }

    func deletePromptRecord(id: UUID) {
        var state = loadState()
        state.prompts.removeAll { $0.id == id }
        saveState(state)
    }

    private func loadState() -> PersistedState {
        store.load(PersistedState.self, forKey: storageKey) ?? PersistedState()
    }

    private func saveState(_ state: PersistedState) {
        store.save(state, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

final class SystemPromptManager {
    private let store: any SystemPromptStore

    init(store: any SystemPromptStore = UserDefaultsSystemPromptStore.shared) {
        self.store = store
    }

    func savedPrompts() -> [SystemPromptRecord] {
        store.loadPrompts()
    }

    func makePromptDraft() -> SystemPromptRecord {
        SystemPromptRecord()
    }

    func savePrompt(_ prompt: SystemPromptRecord) {
        store.savePromptRecord(prompt)
    }

    func deletePrompt(id: UUID) {
        store.deletePromptRecord(id: id)
    }
}
