//
//  MCPServerStore.swift
//  UniLLMs
//
//  Stores MCP server configuration.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol MCPServerStore {
    func loadServers() -> [MCPServerRecord]
    func makeServerDraft() -> MCPServerRecord
    func saveServerRecord(_ server: MCPServerRecord)
    func deleteServerRecord(id: UUID)
    func moveServer(from sourceIndex: Int, to destinationIndex: Int)
}

final class UserDefaultsMCPServerStore: MCPServerStore {
    static let shared = UserDefaultsMCPServerStore()
    static let didChangeNotification = Notification.Name("UserDefaultsMCPServerStoreDidChange")

    private struct PersistedState: Codable, Equatable {
        var servers: [MCPServerRecord]

        init(servers: [MCPServerRecord] = []) {
            self.servers = servers
        }

        private enum CodingKeys: String, CodingKey {
            case servers
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            servers = try container.decodeIfPresent([MCPServerRecord].self, forKey: .servers) ?? []
        }
    }

    private let store: UserDefaultsStore
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "mcpServerConfigurations.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults)
        self.storageKey = storageKey
    }

    func loadServers() -> [MCPServerRecord] {
        loadState().servers
    }

    func makeServerDraft() -> MCPServerRecord {
        MCPServerRecord(name: "")
    }

    func saveServerRecord(_ server: MCPServerRecord) {
        var state = loadState()
        if let index = state.servers.firstIndex(where: { $0.id == server.id }) {
            state.servers[index] = server
        } else {
            state.servers.append(server)
        }
        saveState(state)
    }

    func deleteServerRecord(id: UUID) {
        var state = loadState()
        state.servers.removeAll { $0.id == id }
        saveState(state)
    }

    func moveServer(from sourceIndex: Int, to destinationIndex: Int) {
        var state = loadState()
        guard state.servers.indices.contains(sourceIndex),
              state.servers.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }

        let server = state.servers.remove(at: sourceIndex)
        state.servers.insert(server, at: destinationIndex)
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
