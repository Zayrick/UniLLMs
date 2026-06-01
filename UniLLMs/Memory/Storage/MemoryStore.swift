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
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "memoryRecords.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults)
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
        var state = loadState()
        let previousState = state
        if let index = state.memories.firstIndex(where: { $0.id == memory.id }) {
            state.memories[index] = memory
        } else {
            state.memories.append(memory)
        }
        saveState(state, replacing: previousState)
    }

    func deleteMemory(id: UUID) async throws {
        var state = loadState()
        let previousState = state
        state.memories.removeAll {
            $0.id == id
        }
        saveState(state, replacing: previousState)
    }

    func deleteMemories(scope: MemoryScope?) async throws {
        var state = loadState()
        let previousState = state
        if let scope {
            state.memories.removeAll {
                $0.scope == scope
            }
        } else {
            state.memories = []
        }
        saveState(state, replacing: previousState)
    }

    private func loadState() -> PersistedState {
        store.load(PersistedState.self, forKey: storageKey) ?? PersistedState()
    }

    private func saveState(_ state: PersistedState, replacing previousState: PersistedState) {
        guard state != previousState else {
            return
        }

        store.save(state, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
