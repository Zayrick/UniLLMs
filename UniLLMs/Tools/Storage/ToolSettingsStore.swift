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
    func loadApprovalSkippedToolIDs() -> Set<String>
    func saveApprovalSkippedToolIDs(_ ids: Set<String>)
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

    func isApprovalSkipped(forToolID toolID: String) -> Bool {
        loadApprovalSkippedToolIDs().contains(toolID)
    }

    func saveApprovalSkipped(_ isSkipped: Bool, forToolID toolID: String) {
        var skippedToolIDs = loadApprovalSkippedToolIDs()
        if isSkipped {
            skippedToolIDs.insert(toolID)
        } else {
            skippedToolIDs.remove(toolID)
        }
        saveApprovalSkippedToolIDs(skippedToolIDs)
    }
}

final class UserDefaultsToolSettingsStore: ToolSettingsStore {
    static let shared = UserDefaultsToolSettingsStore()
    static let didChangeNotification = Notification.Name("UserDefaultsToolSettingsStoreDidChange")

    private struct PersistedState: Codable, Equatable {
        var toolsEnabled: Bool
        var disabledBuiltInToolIDs: [String]
        var approvalSkippedToolIDs: [String]

        init(
            toolsEnabled: Bool = false,
            disabledBuiltInToolIDs: [String] = [],
            approvalSkippedToolIDs: [String] = []
        ) {
            self.toolsEnabled = toolsEnabled
            self.disabledBuiltInToolIDs = disabledBuiltInToolIDs
            self.approvalSkippedToolIDs = approvalSkippedToolIDs
        }

        private enum CodingKeys: String, CodingKey {
            case toolsEnabled
            case disabledBuiltInToolIDs
            case approvalSkippedToolIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            toolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolsEnabled) ?? false
            disabledBuiltInToolIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .disabledBuiltInToolIDs
            ) ?? []
            approvalSkippedToolIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .approvalSkippedToolIDs
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

    func loadApprovalSkippedToolIDs() -> Set<String> {
        Set(loadState().approvalSkippedToolIDs)
    }

    func saveApprovalSkippedToolIDs(_ ids: Set<String>) {
        var state = loadState()
        let sortedIDs = ids.sorted()
        guard state.approvalSkippedToolIDs != sortedIDs else {
            return
        }

        state.approvalSkippedToolIDs = sortedIDs
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
    private let approvalSkippableToolIDs: Set<String>

    init(
        registry: ToolRegistry,
        store: any ToolSettingsStore,
        approvalSkippableToolIDs: Set<String> = []
    ) {
        self.registry = registry
        self.store = store
        self.approvalSkippableToolIDs = approvalSkippableToolIDs
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

    func enabledBuiltInToolCount(ids: [String]) -> Int {
        ids.filter {
            registry.tool(id: $0) != nil && isBuiltInToolEnabled(id: $0)
        }.count
    }

    func isBuiltInToolEnabled(id: String) -> Bool {
        store.isBuiltInToolEnabled(id: id)
    }

    func approvalSkippedToolIDs() -> Set<String> {
        store.loadApprovalSkippedToolIDs().filter(isApprovalSkippableToolID)
    }

    func isApprovalSkipped(forToolID toolID: String) -> Bool {
        isApprovalSkippableToolID(toolID) && store.isApprovalSkipped(forToolID: toolID)
    }

    func setApprovalSkipped(_ isSkipped: Bool, forToolID toolID: String) {
        guard isApprovalSkippableToolID(toolID) else {
            return
        }

        store.saveApprovalSkipped(isSkipped, forToolID: toolID)
    }

    func setApprovalSkipped(_ isSkipped: Bool, forToolIDs toolIDs: [String]) {
        let toolIDs = toolIDs.filter(isApprovalSkippableToolID)
        guard !toolIDs.isEmpty else {
            return
        }

        var skippedToolIDs = store.loadApprovalSkippedToolIDs()
        for toolID in toolIDs {
            if isSkipped {
                skippedToolIDs.insert(toolID)
            } else {
                skippedToolIDs.remove(toolID)
            }
        }
        store.saveApprovalSkippedToolIDs(skippedToolIDs)
    }

    private func isApprovalSkippableToolID(_ toolID: String) -> Bool {
        registry.tool(id: toolID) != nil && approvalSkippableToolIDs.contains(toolID)
    }

    @discardableResult
    func setBuiltInTool(id: String, isEnabled: Bool) -> Bool {
        guard registry.tool(id: id) != nil else {
            return false
        }

        store.saveBuiltInToolEnabled(isEnabled, id: id)
        return true
    }

    @discardableResult
    func setBuiltInTools(ids: [String], isEnabled: Bool) -> Bool {
        let registeredIDs = ids.filter {
            registry.tool(id: $0) != nil
        }
        guard !registeredIDs.isEmpty else {
            return false
        }

        var disabledToolIDs = store.loadDisabledBuiltInToolIDs()
        if isEnabled {
            registeredIDs.forEach {
                disabledToolIDs.remove($0)
            }
        } else {
            registeredIDs.forEach {
                disabledToolIDs.insert($0)
            }
        }
        store.saveDisabledBuiltInToolIDs(disabledToolIDs)
        return true
    }
}
