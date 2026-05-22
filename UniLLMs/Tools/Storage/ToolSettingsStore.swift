//
//  ToolSettingsStore.swift
//  UniLLMs
//
//  Persists global tool-call settings and per built-in tool enablement.
//  Created by Zayrick on 2026/5/16.
//

import Foundation

protocol ToolSettingsStore {
    func loadToolsEnabled() -> Bool
    func saveToolsEnabled(_ isEnabled: Bool)
    func loadDisabledBuiltInToolIDs() -> Set<String>
    func saveDisabledBuiltInToolIDs(_ ids: Set<String>)
}

extension ToolSettingsStore {
    func isBuiltInToolEnabled(id: String) -> Bool {
        !loadDisabledBuiltInToolIDs().contains(id)
    }

    func saveBuiltInToolEnabled(_ isEnabled: Bool, id: String) {
        var disabledToolIDs = loadDisabledBuiltInToolIDs()
        if isEnabled {
            disabledToolIDs.remove(id)
        } else {
            disabledToolIDs.insert(id)
        }
        saveDisabledBuiltInToolIDs(disabledToolIDs)
    }
}

final class UserDefaultsToolSettingsStore: ToolSettingsStore {
    static let shared = UserDefaultsToolSettingsStore()
    static let didChangeNotification = Notification.Name("UserDefaultsToolSettingsStoreDidChange")

    private struct PersistedState: Codable, Equatable {
        var toolsEnabled: Bool
        var disabledBuiltInToolIDs: [String]

        init(
            toolsEnabled: Bool = false,
            disabledBuiltInToolIDs: [String] = []
        ) {
            self.toolsEnabled = toolsEnabled
            self.disabledBuiltInToolIDs = disabledBuiltInToolIDs
        }

        private enum CodingKeys: String, CodingKey {
            case toolsEnabled
            case disabledBuiltInToolIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            toolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolsEnabled) ?? false
            disabledBuiltInToolIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .disabledBuiltInToolIDs
            ) ?? []
        }
    }

    private struct LegacyMCPToolState: Decodable {
        var toolsEnabled: Bool?
    }

    private let store: UserDefaultsStore
    private let storageKey: String
    private let legacyMCPStorageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "toolSettings.v1",
        legacyMCPStorageKey: String = "mcpServerConfigurations.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults)
        self.storageKey = storageKey
        self.legacyMCPStorageKey = legacyMCPStorageKey
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

    func loadDisabledBuiltInToolIDs() -> Set<String> {
        Set(loadState().disabledBuiltInToolIDs)
    }

    func saveDisabledBuiltInToolIDs(_ ids: Set<String>) {
        var state = loadState()
        let sortedIDs = ids.sorted()
        guard state.disabledBuiltInToolIDs != sortedIDs else {
            return
        }

        state.disabledBuiltInToolIDs = sortedIDs
        saveState(state)
    }

    private func loadState() -> PersistedState {
        if let state = store.load(PersistedState.self, forKey: storageKey) {
            return state
        }

        guard let legacyToolsEnabled = loadLegacyToolsEnabled() else {
            return PersistedState()
        }

        let migratedState = PersistedState(toolsEnabled: legacyToolsEnabled)
        store.save(migratedState, forKey: storageKey)
        return migratedState
    }

    private func saveState(_ state: PersistedState) {
        store.save(state, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func loadLegacyToolsEnabled() -> Bool? {
        store.load(LegacyMCPToolState.self, forKey: legacyMCPStorageKey)?.toolsEnabled
    }
}

final class ToolSettingsManager {
    private let registry: ToolRegistry
    private let store: any ToolSettingsStore

    init(
        registry: ToolRegistry,
        store: any ToolSettingsStore
    ) {
        self.registry = registry
        self.store = store
    }

    var isToolsEnabled: Bool {
        get {
            store.loadToolsEnabled()
        }
        set {
            store.saveToolsEnabled(newValue)
        }
    }

    func registeredBuiltInTools() -> [ToolDefinition] {
        registry.tools.map(\.definition)
    }

    func isBuiltInToolEnabled(id: String) -> Bool {
        store.isBuiltInToolEnabled(id: id)
    }

    @discardableResult
    func setBuiltInTool(id: String, isEnabled: Bool) -> Bool {
        guard registry.tool(id: id) != nil else {
            return false
        }

        store.saveBuiltInToolEnabled(isEnabled, id: id)
        return true
    }
}
