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
    private let notificationCenter: NotificationCenter
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        storageKey: String = "memoryInjectionSettings.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults, notificationCenter: notificationCenter)
        self.notificationCenter = notificationCenter
        self.storageKey = storageKey
    }

    func loadInjectionSettings() -> MemoryInjectionSettings {
        store.load(MemoryInjectionSettings.self, forKey: storageKey) ?? MemoryInjectionSettings()
    }

    func saveInjectionSettings(_ settings: MemoryInjectionSettings) {
        let normalizedSettings = MemoryInjectionSettings(
            isEnabled: settings.isEnabled,
            filter: settings.filter,
            maximumMemories: settings.maximumMemories
        )
        store.save(normalizedSettings, replacing: loadInjectionSettings(), forKey: storageKey) {
            notifyDidChange()
        }
    }

    private func notifyDidChange() {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
