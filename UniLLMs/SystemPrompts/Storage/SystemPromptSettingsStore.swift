//
//  SystemPromptSettingsStore.swift
//  UniLLMs
//
//  Persists automatic system prompt context settings.
//

import Foundation

protocol SystemPromptSettingsStore {
    func loadInjectionSettings() -> SystemPromptInjectionSettings
    func saveInjectionSettings(_ settings: SystemPromptInjectionSettings)
}

nonisolated struct SystemPromptInjectionSettings: Codable, Equatable {
    var isCurrentDateEnabled: Bool

    init(isCurrentDateEnabled: Bool = false) {
        self.isCurrentDateEnabled = isCurrentDateEnabled
    }
}

final class UserDefaultsSystemPromptSettingsStore: SystemPromptSettingsStore {
    static let shared = UserDefaultsSystemPromptSettingsStore()
    static let didChangeNotification = Notification.Name("UserDefaultsSystemPromptSettingsStoreDidChange")

    private let store: UserDefaultsStore
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "systemPromptInjectionSettings.v1"
    ) {
        store = UserDefaultsStore(defaults: defaults)
        self.storageKey = storageKey
    }

    func loadInjectionSettings() -> SystemPromptInjectionSettings {
        store.load(SystemPromptInjectionSettings.self, forKey: storageKey) ?? SystemPromptInjectionSettings()
    }

    func saveInjectionSettings(_ settings: SystemPromptInjectionSettings) {
        guard settings != loadInjectionSettings() else {
            return
        }

        store.save(settings, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
