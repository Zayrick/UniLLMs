//
//  SystemPromptStore.swift
//  UniLLMs
//
//  Persists user-created system prompt records.
//  Created by Zayrick on 2026/5/19.
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
    private let notificationCenter: NotificationCenter
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        storageKey: String = "systemPromptConfigurations.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults, notificationCenter: notificationCenter)
        self.notificationCenter = notificationCenter
        self.storageKey = storageKey
    }

    func loadPrompts() -> [SystemPromptRecord] {
        loadState().prompts
    }

    func savePromptRecord(_ prompt: SystemPromptRecord) {
        updateState { state in
            if let index = state.prompts.firstIndex(where: { $0.id == prompt.id }) {
                state.prompts[index] = prompt
            } else {
                state.prompts.append(prompt)
            }
        }
    }

    func deletePromptRecord(id: UUID) {
        updateState { state in
            state.prompts.removeAll { $0.id == id }
        }
    }

    private func loadState() -> PersistedState {
        store.load(PersistedState.self, forKey: storageKey) ?? PersistedState()
    }

    private func updateState(_ mutate: (inout PersistedState) -> Void) {
        store.update(PersistedState.self, forKey: storageKey, defaultValue: PersistedState()) { state in
            mutate(&state)
        } didSave: {
            notifyDidChange()
        }
    }

    private func notifyDidChange() {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}

final class SystemPromptManager {
    private let store: any SystemPromptStore
    private let clock: any AppClock

    init(
        store: any SystemPromptStore = UserDefaultsSystemPromptStore.shared,
        clock: any AppClock = SystemAppClock()
    ) {
        self.store = store
        self.clock = clock
    }

    func savedPrompts() -> [SystemPromptRecord] {
        store.loadPrompts()
    }

    func prompt(id: UUID) -> SystemPromptRecord? {
        savedPrompts().first { $0.id == id }
    }

    func makePromptDraft() -> SystemPromptRecord {
        let now = clock.now
        return SystemPromptRecord(createdAt: now, updatedAt: now)
    }

    @discardableResult
    func savePrompt(_ prompt: SystemPromptRecord) -> SystemPromptRecord {
        var promptForSaving = prompt
        promptForSaving.updatedAt = clock.now
        store.savePromptRecord(promptForSaving)
        return promptForSaving
    }

    func deletePrompt(id: UUID) {
        store.deletePromptRecord(id: id)
    }
}
