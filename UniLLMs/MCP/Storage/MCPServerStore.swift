//
//  MCPServerStore.swift
//  UniLLMs
//
//  Stores MCP server configuration and tool-call settings.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol MCPServerStore {
    func loadToolsEnabled() -> Bool
    func saveToolsEnabled(_ isEnabled: Bool)
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
        var toolsEnabled: Bool
        var servers: [MCPServerRecord]
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

    func loadToolsEnabled() -> Bool {
        loadState().toolsEnabled
    }

    func saveToolsEnabled(_ isEnabled: Bool) {
        var state = loadState()
        guard state.toolsEnabled != isEnabled else {
            return
        }

        state.toolsEnabled = isEnabled
        saveState(state)
    }

    func loadServers() -> [MCPServerRecord] {
        loadState().servers
    }

    func makeServerDraft() -> MCPServerRecord {
        let servers = loadServers()
        return MCPServerRecord(
            name: makeUniqueServerName(
                baseName: "MCP Server",
                existingServers: servers
            )
        )
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
        store.load(PersistedState.self, forKey: storageKey) ?? PersistedState(toolsEnabled: false, servers: [])
    }

    private func saveState(_ state: PersistedState) {
        store.save(state, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func makeUniqueServerName(
        baseName: String,
        existingServers: [MCPServerRecord]
    ) -> String {
        let existingNames = Set(existingServers.map(\.name))

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
