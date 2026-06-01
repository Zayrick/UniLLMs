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
