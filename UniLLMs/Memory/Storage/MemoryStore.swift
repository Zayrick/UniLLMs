//
//  MemoryStore.swift
//  UniLLMs
//
//  Declares and implements lightweight saved-memory persistence.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol MemoryStore {
    func fetchMemories(scope: MemoryScope?) async throws -> [MemoryRecord]
    func saveMemory(_ memory: MemoryRecord) async throws
    func deleteMemory(id: UUID) async throws
    func deleteMemories(scope: MemoryScope?) async throws
}

final class UserDefaultsMemoryStore: MemoryStore {
    static let shared = UserDefaultsMemoryStore()
    static let didChangeNotification = Notification.Name("UserDefaultsMemoryStoreDidChange")

    private struct PersistedState: Codable, Equatable {
        var memories: [MemoryRecord]

        init(memories: [MemoryRecord] = []) {
            self.memories = memories
        }

        private enum CodingKeys: String, CodingKey {
            case memories
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            memories = try container.decodeIfPresent([MemoryRecord].self, forKey: .memories) ?? []
        }
    }

    private let store: UserDefaultsStore
    private let notificationCenter: NotificationCenter
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        storageKey: String = "memoryRecords.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults, notificationCenter: notificationCenter)
        self.notificationCenter = notificationCenter
        self.storageKey = storageKey
    }

    func fetchMemories(scope: MemoryScope?) async throws -> [MemoryRecord] {
        let memories = loadState().memories
        guard let scope else {
            return memories
        }

        return memories.filter {
            $0.scope == scope
        }
    }

    func saveMemory(_ memory: MemoryRecord) async throws {
        try updateState { state in
            if let index = state.memories.firstIndex(where: { $0.id == memory.id }) {
                state.memories[index] = memory
            } else {
                state.memories.append(memory)
            }
        }
    }

    func deleteMemory(id: UUID) async throws {
        try updateState { state in
            state.memories.removeAll {
                $0.id == id
            }
        }
    }

    func deleteMemories(scope: MemoryScope?) async throws {
        try updateState { state in
            if let scope {
                state.memories.removeAll {
                    $0.scope == scope
                }
            } else {
                state.memories = []
            }
        }
    }

    private func loadState() -> PersistedState {
        store.load(PersistedState.self, forKey: storageKey) ?? PersistedState()
    }

    private func updateState(_ mutate: (inout PersistedState) -> Void) throws {
        try store.updateOrThrow(PersistedState.self, forKey: storageKey, defaultValue: PersistedState()) { state in
            mutate(&state)
        } didSave: {
            notifyDidChange()
        }
    }

    private func notifyDidChange() {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
