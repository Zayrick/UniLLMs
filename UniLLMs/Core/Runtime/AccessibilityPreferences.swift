//
//  AccessibilityPreferences.swift
//  UniLLMs
//
//  Centralizes UIKit accessibility preference reads behind a small audited API.
//

import UIKit

@safe enum AccessibilityPreferences {
    static var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    static var reduceMotionStatusDidChangeNotification: Notification.Name {
        UIAccessibility.reduceMotionStatusDidChangeNotification
    }
}
