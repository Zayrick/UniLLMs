//
//  ToolSettingsStoreTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ToolSettingsStoreTests: UserDefaultsBackedTestCase {
    func testToolSettingsStorePersistsGlobalAndBuiltInToolEnablement() {
        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "toolSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )

        XCTAssertFalse(settingsStore.loadToolsEnabled())
        XCTAssertTrue(settingsStore.isBuiltInToolEnabled(id: "current_datetime"))

        settingsStore.saveToolsEnabled(true)
        settingsStore.saveBuiltInToolEnabled(false, id: "current_datetime")

        let reloadedStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "toolSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )

        XCTAssertTrue(reloadedStore.loadToolsEnabled())
        XCTAssertFalse(reloadedStore.isBuiltInToolEnabled(id: "current_datetime"))

        reloadedStore.saveBuiltInToolEnabled(true, id: "current_datetime")

        XCTAssertTrue(reloadedStore.isBuiltInToolEnabled(id: "current_datetime"))
    }

    func testToolSettingsStoreReadsLegacyMCPGlobalToolsEnabled() throws {
        let legacyJSON = #"{"toolsEnabled":true,"servers":[]}"#
        defaults.set(try XCTUnwrap(legacyJSON.data(using: .utf8)), forKey: "legacyMCPSettings")

        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "missingToolSettings",
            legacyMCPStorageKey: "legacyMCPSettings"
        )

        XCTAssertTrue(settingsStore.loadToolsEnabled())

        let migratedStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "missingToolSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )

        XCTAssertTrue(migratedStore.loadToolsEnabled())
    }

    func testToolSettingsStoreIgnoresLegacyMCPStateWithoutGlobalToolsEnabled() throws {
        let legacyJSON = #"{"servers":[{"name":"Team Tools"}]}"#
        defaults.set(try XCTUnwrap(legacyJSON.data(using: .utf8)), forKey: "legacyMCPSettings")

        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "serverOnlyLegacyToolSettings",
            legacyMCPStorageKey: "legacyMCPSettings"
        )

        XCTAssertFalse(settingsStore.loadToolsEnabled())

        settingsStore.saveToolsEnabled(true)

        XCTAssertTrue(settingsStore.loadToolsEnabled())
    }

    func testToolSettingsStorePostsOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "toolNotificationSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )
        let injectedObserver = StoreNotificationObserver(
            name: UserDefaultsToolSettingsStore.didChangeNotification,
            object: settingsStore,
            notificationCenter: notificationCenter
        )
        let defaultObserver = StoreNotificationObserver(
            name: UserDefaultsToolSettingsStore.didChangeNotification,
            object: settingsStore,
            notificationCenter: .default
        )
        defer {
            injectedObserver.invalidate()
            defaultObserver.invalidate()
        }

        settingsStore.saveToolsEnabled(true)

        XCTAssertEqual(injectedObserver.notificationCount, 1)
        XCTAssertEqual(defaultObserver.notificationCount, 0)
    }

    func testToolSettingsManagerUpdatesBuiltInToolsAsGroup() {
        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "toolGroupSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )
        let registry = ToolRegistry(tools: [
            SettingsTool(name: "memory_add"),
            SettingsTool(name: "memory_delete"),
            SettingsTool(name: "current_datetime")
        ])
        let manager = ToolSettingsManager(registry: registry, store: settingsStore)

        XCTAssertEqual(manager.enabledBuiltInToolCount(ids: ["memory_add", "memory_delete"]), 2)

        manager.setBuiltInTools(ids: ["memory_add", "memory_delete"], isEnabled: false)

        XCTAssertEqual(manager.enabledBuiltInToolCount(ids: ["memory_add", "memory_delete"]), 0)
        XCTAssertTrue(manager.isBuiltInToolEnabled(id: "current_datetime"))

        manager.setBuiltInTools(ids: ["memory_add", "memory_delete"], isEnabled: true)

        XCTAssertEqual(manager.enabledBuiltInToolCount(ids: ["memory_add", "memory_delete"]), 2)
    }
}

private struct SettingsTool: Tool {
    let definition: ToolDefinition

    init(name: String) {
        definition = ToolDefinition(name: name, summary: "")
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, content: "")
    }
}
