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

    func testMemoryManagerSearchesCaseInsensitiveTerms() async throws {
        let store = UserDefaultsMemoryStore(
            defaults: defaults,
            storageKey: "memoryManager"
        )
        let manager = MemoryManager(store: store)
        try await manager.saveMemory(
            MemoryRecord(scope: .user, text: "User prefers concise Chinese responses.")
        )
        try await manager.saveMemory(
            MemoryRecord(scope: .user, text: "User lives in Shanghai.")
        )

        let matches = try await manager.searchMemories(query: "concise chinese", scope: .user)

        XCTAssertEqual(matches.map(\.text), ["User prefers concise Chinese responses."])
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
                timeRange: .last7Days,
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
            for: ChatContext(messages: [ChatMessage(role: .user, content: "")])
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
            MemoryRecord(scope: .user, text: "User likes concise answers.")
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [ChatMessage(role: .user, content: "answers")])
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
                timeRange: .all,
                maximumMemories: 1
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        try await store.saveMemory(
            MemoryRecord(scope: .user, text: "User prefers concise answers.")
        )

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [ChatMessage(role: .user, content: "travel plans")])
        )

        XCTAssertEqual(memories.map(\.text), ["User prefers concise answers."])
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
                timeRange: .all,
                maximumMemories: nil
            )
        )
        let manager = MemoryManager(
            store: store,
            settingsStore: settingsStore
        )
        try await store.saveMemory(MemoryRecord(scope: .user, text: "First memory"))
        try await store.saveMemory(MemoryRecord(scope: .user, text: "Second memory"))

        let memories = try await manager.retrieveRelevantMemories(
            for: ChatContext(messages: [ChatMessage(role: .user, content: "")])
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
        try await manager.saveMemory(MemoryRecord(scope: .user, text: "User memory"))
        try await manager.saveMemory(MemoryRecord(scope: .session, text: "Session memory"))

        let deletedCount = try await manager.deleteAllMemories(scope: .user)

        XCTAssertEqual(deletedCount, 1)
        let userMemories = try await manager.savedMemories(scope: .user)
        let sessionMemories = try await manager.savedMemories(scope: .session)
        XCTAssertTrue(userMemories.isEmpty)
        XCTAssertEqual(sessionMemories.map(\.text), ["Session memory"])
    }
}
