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
    private let notificationCenter: NotificationCenter
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        storageKey: String = "mcpServerConfigurations.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults, notificationCenter: notificationCenter)
        self.notificationCenter = notificationCenter
        self.storageKey = storageKey
    }

    func loadServers() -> [MCPServerRecord] {
        loadState().servers
    }

    func saveServerRecord(_ server: MCPServerRecord) {
        updateState { state in
            if let index = state.servers.firstIndex(where: { $0.id == server.id }) {
                state.servers[index] = server
            } else {
                state.servers.append(server)
            }
        }
    }

    func deleteServerRecord(id: UUID) {
        updateState { state in
            state.servers.removeAll { $0.id == id }
        }
    }

    func moveServer(from sourceIndex: Int, to destinationIndex: Int) {
        updateState { state in
            guard state.servers.indices.contains(sourceIndex),
                  state.servers.indices.contains(destinationIndex),
                  sourceIndex != destinationIndex else {
                return
            }

            let server = state.servers.remove(at: sourceIndex)
            state.servers.insert(server, at: destinationIndex)
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
