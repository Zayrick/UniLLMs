//
//  UserDefaultsBackedStoreFailureNotificationTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class UserDefaultsBackedStoreFailureNotificationTests: UserDefaultsBackedTestCase {
    func testChatStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() async throws {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "chatHistory")
        let store = UserDefaultsChatStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "chatHistory"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        let sessions = try await store.fetchSessions()

        XCTAssertTrue(sessions.isEmpty)
        assertUserDefaultsFailure(observers, expectedKey: "chatHistory")
    }

    func testLLMProviderStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "providers")
        let store = LLMProviderStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "providers"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        XCTAssertTrue(store.fetchProviders().isEmpty)
        assertUserDefaultsFailure(observers, expectedKey: "providers")
    }

    func testMCPServerStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "mcpServers")
        let store = UserDefaultsMCPServerStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "mcpServers"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        XCTAssertTrue(store.loadServers().isEmpty)
        assertUserDefaultsFailure(observers, expectedKey: "mcpServers")
    }

    func testMemoryStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() async throws {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "memories")
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "memories"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        let memories = try await store.fetchMemories(scope: .user)

        XCTAssertTrue(memories.isEmpty)
        assertUserDefaultsFailure(observers, expectedKey: "memories")
    }

    func testMemorySettingsStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "memorySettings")
        let store = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "memorySettings"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        _ = store.loadInjectionSettings()

        assertUserDefaultsFailure(observers, expectedKey: "memorySettings")
    }

    func testSystemPromptStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "systemPrompts")
        let store = UserDefaultsSystemPromptStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "systemPrompts"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        XCTAssertTrue(store.loadPrompts().isEmpty)
        assertUserDefaultsFailure(observers, expectedKey: "systemPrompts")
    }

    func testSystemPromptSettingsStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "systemPromptSettings")
        let store = UserDefaultsSystemPromptSettingsStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "systemPromptSettings"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        _ = store.loadInjectionSettings()

        assertUserDefaultsFailure(observers, expectedKey: "systemPromptSettings")
    }

    func testToolSettingsStoreUserDefaultsFailuresPostOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        corruptStoredData(forKey: "toolSettings")
        let store = UserDefaultsToolSettingsStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "toolSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )
        let observers = makeFailureObservers(notificationCenter: notificationCenter)
        defer {
            observers.injected.invalidate()
            observers.defaultCenter.invalidate()
        }

        XCTAssertFalse(store.loadToolsEnabled())
        assertUserDefaultsFailure(observers, expectedKey: "toolSettings")
    }

    private func corruptStoredData(forKey key: String) {
        defaults.set(Data("not-json".utf8), forKey: key)
    }

    private func makeFailureObservers(
        notificationCenter: NotificationCenter
    ) -> (
        injected: UserDefaultsStoreFailureObserver,
        defaultCenter: UserDefaultsStoreFailureObserver
    ) {
        (
            injected: UserDefaultsStoreFailureObserver(notificationCenter: notificationCenter),
            defaultCenter: UserDefaultsStoreFailureObserver(notificationCenter: .default)
        )
    }

    private func assertUserDefaultsFailure(
        _ observers: (
            injected: UserDefaultsStoreFailureObserver,
            defaultCenter: UserDefaultsStoreFailureObserver
        ),
        expectedKey: String
    ) {
        XCTAssertEqual(observers.injected.failures.map(\.operation), [.load])
        XCTAssertEqual(observers.injected.failures.map(\.key), [expectedKey])
        XCTAssertTrue(observers.defaultCenter.failures.isEmpty)
    }
}
