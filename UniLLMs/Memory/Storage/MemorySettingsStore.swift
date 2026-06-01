//
//  MemorySettingsStore.swift
//  UniLLMs
//
//  Persists memory injection settings.
//

import Foundation

protocol MemorySettingsStore {
    func loadInjectionSettings() -> MemoryInjectionSettings
    func saveInjectionSettings(_ settings: MemoryInjectionSettings)
}

final class UserDefaultsMemorySettingsStore: MemorySettingsStore {
    static let shared = UserDefaultsMemorySettingsStore()
    static let didChangeNotification = Notification.Name("UserDefaultsMemorySettingsStoreDidChange")

    private let store: UserDefaultsStore
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "memoryInjectionSettings.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults)
        self.storageKey = storageKey
    }

    func loadInjectionSettings() -> MemoryInjectionSettings {
        store.load(MemoryInjectionSettings.self, forKey: storageKey) ?? MemoryInjectionSettings()
    }

    func saveInjectionSettings(_ settings: MemoryInjectionSettings) {
        let normalizedSettings = MemoryInjectionSettings(
            isEnabled: settings.isEnabled,
            timeRange: settings.timeRange,
            maximumMemories: settings.maximumMemories
        )
        guard normalizedSettings != loadInjectionSettings() else {
            return
        }

        store.save(normalizedSettings, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
