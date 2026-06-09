//
//  AppSettingsStore.swift
//  UniLLMs
//
//  Stores app-wide user settings.
//  Created by Codex on 2026/6/3.
//

import Foundation

enum AppColorMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
}

protocol AppSettingsStore: AnyObject {
    var isBackgroundRuntimeEnabled: Bool { get set }
    var colorMode: AppColorMode { get set }
    var keepsScreenAwakeDuringAIOutput: Bool { get set }
}

final class UserDefaultsAppSettingsStore: AppSettingsStore {
    static let shared = UserDefaultsAppSettingsStore()

    private enum Key {
        static let backgroundRuntimeEnabled = "appSettings.backgroundRuntimeEnabled"
        static let colorMode = "appSettings.colorMode"
        static let keepsScreenAwakeDuringAIOutput = "appSettings.keepsScreenAwakeDuringAIOutput"
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

    var colorMode: AppColorMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.colorMode),
                  let mode = AppColorMode(rawValue: rawValue) else {
                return .system
            }

            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.colorMode)
        }
    }

    var keepsScreenAwakeDuringAIOutput: Bool {
        get {
            defaults.bool(forKey: Key.keepsScreenAwakeDuringAIOutput)
        }
        set {
            defaults.set(newValue, forKey: Key.keepsScreenAwakeDuringAIOutput)
        }
    }
}
