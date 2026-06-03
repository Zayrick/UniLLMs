//
//  AppSettingsStore.swift
//  UniLLMs
//
//  Stores app-wide user settings.
//  Created by Codex on 2026/6/3.
//

import Foundation

protocol AppSettingsStore: AnyObject {
    var isBackgroundRuntimeEnabled: Bool { get set }
}

final class UserDefaultsAppSettingsStore: AppSettingsStore {
    static let shared = UserDefaultsAppSettingsStore()

    private enum Key {
        static let backgroundRuntimeEnabled = "appSettings.backgroundRuntimeEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isBackgroundRuntimeEnabled: Bool {
        get {
            defaults.bool(forKey: Key.backgroundRuntimeEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.backgroundRuntimeEnabled)
        }
    }
}
