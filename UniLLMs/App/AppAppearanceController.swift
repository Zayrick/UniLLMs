//
//  AppAppearanceController.swift
//  UniLLMs
//
//  Applies app-wide UIKit appearance preferences.
//

import UIKit

@MainActor
enum AppAppearanceController {
    static func apply(_ colorMode: AppColorMode, to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = colorMode.userInterfaceStyle
    }

    static func apply(_ colorMode: AppColorMode) {
        apply(colorMode, to: UIApplication.shared)
    }

    static func apply(_ colorMode: AppColorMode, to application: UIApplication) {
        application.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { window in
                apply(colorMode, to: window)
            }
    }
}

private extension AppColorMode {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
