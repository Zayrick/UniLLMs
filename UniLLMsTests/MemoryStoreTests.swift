//
//  MemoryStoreTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class MemoryStoreTests: UserDefaultsBackedTestCase {
    func testMemoryStorePersistsUpdatesAndDeletesRecords() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "memories"
        )
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let memory = MemoryRecord(
            scope: .user,
            text: "User likes concise answers.",
            createdAt: createdAt
        )

        try await store.saveMemory(memory)

        var savedMemories = try await store.fetchMemories(scope: .user)
        XCTAssertEqual(savedMemories, [memory])

        var updatedMemory = memory
        updatedMemory.text = "User likes concise answers in Chinese."
        updatedMemory.updatedAt = updatedAt

        try await store.saveMemory(updatedMemory)

        savedMemories = try await store.fetchMemories(scope: .user)
        XCTAssertEqual(savedMemories, [updatedMemory])

        try await store.deleteMemory(id: memory.id)

        savedMemories = try await store.fetchMemories(scope: .user)
        XCTAssertTrue(savedMemories.isEmpty)
    }

    func testMemoryStorePostsOnlyOnInjectedNotificationCenter() async throws {
        let notificationCenter = NotificationCenter()
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "memories"
        )
        let injectedObserver = StoreNotificationObserver(
            name: UserDefaultsMemoryStore.didChangeNotification,
            object: store,
            notificationCenter: notificationCenter
        )
        let defaultObserver = StoreNotificationObserver(
            name: UserDefaultsMemoryStore.didChangeNotification,
            object: store,
            notificationCenter: .default
        )
        defer {
            injectedObserver.invalidate()
            defaultObserver.invalidate()
        }

        try await store.saveMemory(
            makeMemory(text: "User likes concise answers.")
        )

        XCTAssertEqual(injectedObserver.notificationCount, 1)
        XCTAssertEqual(defaultObserver.notificationCount, 0)
    }

    func testMemoryRecordDecodingDefaultsUpdatedAtToCreatedAt() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "scope": "user",
            "text": "Legacy memory",
            "createdAt": "2026-06-01T10:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let memory = try decoder.decode(MemoryRecord.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(memory.id, id)
        XCTAssertEqual(memory.updatedAt, memory.createdAt)
    }

    func testMemoryInjectionSettingsRoundTripsSmartFilter() throws {
        let settings = MemoryInjectionSettings(
            isEnabled: true,
            filter: .smart,
            maximumMemories: 12
        )

        let data = try JSONEncoder().encode(settings)
        let decodedSettings = try JSONDecoder().decode(MemoryInjectionSettings.self, from: data)

        XCTAssertEqual(decodedSettings, settings)
    }

    func testMemoryInjectionSettingsDefaultsToSmartFilterWithFiveMemories() {
        let settings = MemoryInjectionSettings()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.filter, .smart)
        XCTAssertEqual(settings.maximumMemories, 5)
    }

    func testMemorySettingsStorePostsOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "memorySettings"
        )
        let injectedObserver = StoreNotificationObserver(
            name: UserDefaultsMemorySettingsStore.didChangeNotification,
            object: settingsStore,
            notificationCenter: notificationCenter
        )
        let defaultObserver = StoreNotificationObserver(
            name: UserDefaultsMemorySettingsStore.didChangeNotification,
            object: settingsStore,
            notificationCenter: .default
        )
        defer {
            injectedObserver.invalidate()
            defaultObserver.invalidate()
        }

        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(isEnabled: false)
        )

        XCTAssertEqual(injectedObserver.notificationCount, 1)
        XCTAssertEqual(defaultObserver.notificationCount, 0)
    }

    func testMemoryManagerUsesInjectedClockForDraftAndSaveTimestamps() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_123)
        let clock = MutableClock(now: createdAt)
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "clockedMemoryManager"
        )
        let manager = MemoryManager(store: store, clock: clock)

        let draft = manager.makeMemoryDraft()

        XCTAssertEqual(draft.createdAt, createdAt)
        XCTAssertEqual(draft.updatedAt, createdAt)

        let savedMemory = try await manager.saveMemory(
            scope: .user,
            text: "User likes deterministic manager tests."
        )

        XCTAssertEqual(savedMemory.createdAt, createdAt)
        XCTAssertEqual(savedMemory.updatedAt, createdAt)

        clock.now = updatedAt
        var editedMemory = savedMemory
        editedMemory.text = "User likes deterministic memory manager tests."
        let updatedMemory = try await manager.saveMemory(editedMemory)

        XCTAssertEqual(updatedMemory.createdAt, createdAt)
        XCTAssertEqual(updatedMemory.updatedAt, updatedAt)
        let savedMemories = try await manager.savedMemories(scope: .user)
        XCTAssertEqual(savedMemories, [updatedMemory])
    }

    func testMemoryManagerSearchesCaseInsensitiveTerms() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "memoryManager"
        )
        let manager = MemoryManager(store: store)
        try await manager.saveMemory(scope: .user, text: "User prefers concise Chinese responses.")
        try await manager.saveMemory(scope: .user, text: "User lives in Shanghai.")

        let matches = try await manager.searchMemories(query: "concise chinese", scope: .user)

        XCTAssertEqual(matches.map(\.text), ["User prefers concise Chinese responses."])
    }

    func testMemoryRetrieverUsesInjectedClockForTimeFilter() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "clockedMemoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "clockedMemoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(
                isEnabled: true,
                filter: .last7Days,
                maximumMemories: nil
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore,
            clock: MutableClock(now: referenceDate)
        )
        try await store.saveMemory(
            MemoryRecord(
                scope: .user,
                text: "Inside clocked range",
                createdAt: referenceDate.addingTimeInterval(-6 * 24 * 60 * 60),
                updatedAt: referenceDate.addingTimeInterval(-6 * 24 * 60 * 60)
            )
        )
        try await store.saveMemory(
            MemoryRecord(
                scope: .user,
                text: "Outside clocked range",
                createdAt: referenceDate.addingTimeInterval(-8 * 24 * 60 * 60),
                updatedAt: referenceDate.addingTimeInterval(-8 * 24 * 60 * 60)
            )
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "")])
        )

        XCTAssertEqual(memories.map(\.text), ["Inside clocked range"])
    }

    func testMemoryRetrieverAppliesInjectionSettingsIntersection() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "memoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "memoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(
                isEnabled: true,
                filter: .last7Days,
                maximumMemories: 1
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        let now = Date()
        try await store.saveMemory(
            MemoryRecord(
                scope: .user,
                text: "Most recent memory",
                createdAt: now.addingTimeInterval(-1 * 24 * 60 * 60),
                updatedAt: now.addingTimeInterval(-1 * 24 * 60 * 60)
            )
        )
        try await store.saveMemory(
            MemoryRecord(
                scope: .user,
                text: "Older in range memory",
                createdAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
                updatedAt: now.addingTimeInterval(-2 * 24 * 60 * 60)
            )
        )
        try await store.saveMemory(
            MemoryRecord(
                scope: .user,
                text: "Outside range memory",
                createdAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
                updatedAt: now.addingTimeInterval(-10 * 24 * 60 * 60)
            )
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "")])
        )

        XCTAssertEqual(memories.map(\.text), ["Most recent memory"])
    }

    func testMemoryRetrieverReturnsNoMemoriesWhenInjectionIsDisabled() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "disabledMemoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "disabledMemoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(isEnabled: false)
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        try await store.saveMemory(
            makeMemory(text: "User likes concise answers.")
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "answers")])
        )

        XCTAssertTrue(memories.isEmpty)
    }

    func testMemoryRetrieverDoesNotFilterInjectedMemoriesByPromptKeywords() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "keywordIndependentMemoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "keywordIndependentMemoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(
                isEnabled: true,
                filter: .all,
                maximumMemories: 1
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        try await store.saveMemory(
            makeMemory(text: "User prefers concise answers.")
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "travel plans")])
        )

        XCTAssertEqual(memories.map(\.text), ["User prefers concise answers."])
    }

    func testMemoryRetrieverSmartFilterRanksPartialKeywordMatches() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "smartMemoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "smartMemoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(
                isEnabled: true,
                filter: .smart,
                maximumMemories: 5
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        let now = Date()
        try await store.saveMemory(
            MemoryRecord(
                scope: .user,
                text: "Travel plans should include trains.",
                createdAt: now.addingTimeInterval(-3),
                updatedAt: now.addingTimeInterval(-3)
            )
        )
        try await store.saveMemory(
            MemoryRecord(
                scope: .user,
                text: "Travel budgets should stay flexible.",
                createdAt: now.addingTimeInterval(-1),
                updatedAt: now.addingTimeInterval(-1)
            )
        )
        try await store.saveMemory(
            makeMemory(text: "User prefers concise answers.")
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "Can you help with my travel plans")])
        )

        XCTAssertEqual(
            memories.map(\.text),
            [
                "Travel plans should include trains.",
                "Travel budgets should stay flexible."
            ]
        )
    }

    func testMemoryRetrieverSmartFilterUsesDefaultMemoryCount() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "defaultSmartMemoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "defaultSmartMemoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(MemoryInjectionSettings())
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        let now = Date()
        for index in 0..<6 {
            try await store.saveMemory(
                MemoryRecord(
                    scope: .user,
                    text: "Travel plan candidate \(index)",
                    createdAt: now.addingTimeInterval(TimeInterval(-index)),
                    updatedAt: now.addingTimeInterval(TimeInterval(-index))
                )
            )
        }

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "travel plan")])
        )

        XCTAssertEqual(memories.count, 5)
        XCTAssertEqual(settingsStore.loadInjectionSettings().maximumMemories, 5)
    }

    func testMemoryRetrieverSmartFilterMatchesCJKBigramsWithoutSingleCharacterFalsePositives() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "cjkSmartMemoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "cjkSmartMemoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(
                isEnabled: true,
                filter: .smart,
                maximumMemories: 5
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        try await store.saveMemory(
            makeMemory(text: "上海旅行应该安排高铁。")
        )
        try await store.saveMemory(
            makeMemory(text: "我喜欢咖啡。")
        )
        try await store.saveMemory(
            makeMemory(text: "User prefers concise answers.")
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "帮我做上海旅行计划")])
        )

        XCTAssertEqual(memories.map(\.text), ["上海旅行应该安排高铁。"])
    }

    func testMemoryRetrieverSupportsUnlimitedInjectionCount() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "unlimitedMemoryRetriever"
        )
        let settingsStore = UserDefaultsMemorySettingsStore(
            defaults: defaults,
            storageKey: "unlimitedMemoryRetrieverSettings"
        )
        settingsStore.saveInjectionSettings(
            MemoryInjectionSettings(
                isEnabled: true,
                filter: .all,
                maximumMemories: nil
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        try await store.saveMemory(makeMemory(text: "First memory"))
        try await store.saveMemory(makeMemory(text: "Second memory"))

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "")])
        )

        XCTAssertEqual(memories.count, 2)
        XCTAssertNil(settingsStore.loadInjectionSettings().maximumMemories)
    }

    func testMemoryManagerDeletesAllMemoriesInScope() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "clearMemoryManager"
        )
        let manager = MemoryManager(store: store)
        try await manager.saveMemory(scope: .user, text: "User memory")
        try await manager.saveMemory(scope: .session, text: "Session memory")

        let deletedCount = try await manager.deleteAllMemories(scope: .user)

        XCTAssertEqual(deletedCount, 1)
        let userMemories = try await manager.savedMemories(scope: .user)
        let sessionMemories = try await manager.savedMemories(scope: .session)
        XCTAssertTrue(userMemories.isEmpty)
        XCTAssertEqual(sessionMemories.map(\.text), ["Session memory"])
    }
}

private final class MutableClock: AppClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private func makeMemory(
    scope: MemoryScope = .user,
    text: String,
    createdAt: Date = Date(timeIntervalSince1970: 1),
    updatedAt: Date? = nil
) -> MemoryRecord {
    MemoryRecord(
        scope: scope,
        text: text,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}
