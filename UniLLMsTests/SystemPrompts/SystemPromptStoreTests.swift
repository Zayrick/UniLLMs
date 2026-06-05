//
//  SystemPromptStoreTests.swift
//  UniLLMsTests
//
//  Covers system prompt persistence behavior.
//  Created by Zayrick on 2026/5/19.
//

import Foundation
import XCTest
@testable import UniLLMs

final class SystemPromptStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: UserDefaultsSystemPromptStore!
    private var manager: SystemPromptManager!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        suiteName = "SystemPromptStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = UserDefaultsSystemPromptStore(defaults: defaults, storageKey: "systemPrompts")
        manager = SystemPromptManager(store: store, clock: FixedClock(now: now))
    }

    override func tearDownWithError() throws {
        if let defaults = defaults, let suiteName = suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        store = nil
        manager = nil
    }

    func testSavingPromptPersistsTitleAndContent() throws {
        let prompt = makePrompt(title: "Translation Assistant", content: "Always answer in Chinese.")

        let savedPrompt = manager.savePrompt(prompt)

        let reloadedStore = UserDefaultsSystemPromptStore(defaults: defaults, storageKey: "systemPrompts")
        let reloadedPrompt = try XCTUnwrap(reloadedStore.loadPrompts().first)
        XCTAssertEqual(reloadedPrompt, savedPrompt)
        XCTAssertEqual(savedPrompt.createdAt, prompt.createdAt)
        XCTAssertEqual(savedPrompt.updatedAt, now)
    }

    func testUpdatingPromptReplacesMatchingUUID() throws {
        let prompt = makePrompt(title: "Translation Assistant", content: "Always answer in Chinese.")
        let savedPrompt = manager.savePrompt(prompt)
        var updatedPrompt = savedPrompt
        updatedPrompt.title = "Code Review"
        updatedPrompt.content = "Review for correctness first."
        updatedPrompt.updatedAt = Date(timeIntervalSince1970: 2)

        let savedUpdatedPrompt = manager.savePrompt(updatedPrompt)

        XCTAssertEqual(manager.savedPrompts(), [savedUpdatedPrompt])
        XCTAssertEqual(savedUpdatedPrompt.updatedAt, now)
    }

    func testDeletingPromptRemovesMatchingUUIDOnly() throws {
        let first = makePrompt(
            title: "Translation Assistant",
            content: "Always answer in Chinese."
        )
        let second = makePrompt(
            title: "Code Review",
            content: "Review for correctness first."
        )
        let savedFirst = manager.savePrompt(first)
        let savedSecond = manager.savePrompt(second)

        manager.deletePrompt(id: savedFirst.id)

        XCTAssertEqual(manager.savedPrompts(), [savedSecond])
    }

    func testDraftDoesNotPersistUntilSaved() {
        let draft = manager.makePromptDraft()

        XCTAssertTrue(manager.savedPrompts().isEmpty)
        XCTAssertEqual(draft.createdAt, now)
        XCTAssertEqual(draft.updatedAt, now)

        manager.savePrompt(draft)

        XCTAssertEqual(manager.savedPrompts(), [draft])
    }

    func testSystemPromptStorePostsOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        let promptStore = UserDefaultsSystemPromptStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "systemPrompts"
        )
        let injectedObserver = StoreNotificationObserver(
            name: UserDefaultsSystemPromptStore.didChangeNotification,
            object: promptStore,
            notificationCenter: notificationCenter
        )
        let defaultObserver = StoreNotificationObserver(
            name: UserDefaultsSystemPromptStore.didChangeNotification,
            object: promptStore,
            notificationCenter: .default
        )
        defer {
            injectedObserver.invalidate()
            defaultObserver.invalidate()
        }

        promptStore.savePromptRecord(
            makePrompt(title: "Review", content: "Review for correctness first.")
        )

        XCTAssertEqual(injectedObserver.notificationCount, 1)
        XCTAssertEqual(defaultObserver.notificationCount, 0)
    }

    func testPromptReturnsMatchingRecordByID() throws {
        let prompt = makePrompt(title: "Translation Assistant", content: "Always answer in Chinese.")
        let otherPrompt = makePrompt(title: "Code Review", content: "Review for correctness first.")
        let savedPrompt = manager.savePrompt(prompt)
        manager.savePrompt(otherPrompt)

        XCTAssertEqual(manager.prompt(id: savedPrompt.id), savedPrompt)
        XCTAssertNil(manager.prompt(id: UUID()))
    }

    func testSystemPromptSettingsStorePostsOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        let settingsStore = UserDefaultsSystemPromptSettingsStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "systemPromptSettings"
        )
        let injectedObserver = StoreNotificationObserver(
            name: UserDefaultsSystemPromptSettingsStore.didChangeNotification,
            object: settingsStore,
            notificationCenter: notificationCenter
        )
        let defaultObserver = StoreNotificationObserver(
            name: UserDefaultsSystemPromptSettingsStore.didChangeNotification,
            object: settingsStore,
            notificationCenter: .default
        )
        defer {
            injectedObserver.invalidate()
            defaultObserver.invalidate()
        }

        settingsStore.saveInjectionSettings(
            SystemPromptInjectionSettings(isCurrentDateEnabled: true)
        )

        XCTAssertEqual(injectedObserver.notificationCount, 1)
        XCTAssertEqual(defaultObserver.notificationCount, 0)
    }

    func testSystemPromptInjectionSettingsPersistCurrentDatePreference() {
        let settingsStore = UserDefaultsSystemPromptSettingsStore(
            defaults: defaults,
            storageKey: "systemPromptSettings"
        )

        XCTAssertFalse(settingsStore.loadInjectionSettings().isCurrentDateEnabled)

        settingsStore.saveInjectionSettings(
            SystemPromptInjectionSettings(isCurrentDateEnabled: true)
        )

        let reloadedStore = UserDefaultsSystemPromptSettingsStore(
            defaults: defaults,
            storageKey: "systemPromptSettings"
        )
        XCTAssertTrue(reloadedStore.loadInjectionSettings().isCurrentDateEnabled)
    }

    private func makePrompt(
        id: UUID = UUID(),
        title: String,
        content: String
    ) -> SystemPromptRecord {
        SystemPromptRecord(
            id: id,
            title: title,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private struct FixedClock: AppClock {
    var now: Date
}
