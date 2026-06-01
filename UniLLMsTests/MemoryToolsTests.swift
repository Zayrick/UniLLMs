//
//  MemoryToolsTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class MemoryToolsTests: UserDefaultsBackedTestCase {
    func testMemoryToolsAddSearchUpdateListAndDeleteMemories() async throws {
        let manager = MemoryManager(
            store: UserDefaultsMemoryStore(
                defaults: defaults,
                storageKey: "memoryTools"
            )
        )
        let context = ToolExecutionContext(session: nil)

        let addResult = try await MemoryAddTool(memoryManager: manager).execute(
            call: ToolCall(
                id: "call_add",
                toolID: "memory_add",
                arguments: ["text": .string("User prefers concise answers.")]
            ),
            context: context
        )

        XCTAssertFalse(addResult.isError)

        var memories = try await manager.savedMemories(scope: .user)
        XCTAssertEqual(memories.map(\.text), ["User prefers concise answers."])
        let memoryID = try XCTUnwrap(memories.first?.id)

        let searchResult = try await MemorySearchTool(memoryManager: manager).execute(
            call: ToolCall(
                id: "call_search",
                toolID: "memory_search",
                arguments: [
                    "query": .string("concise"),
                    "limit": .int(10)
                ]
            ),
            context: context
        )

        XCTAssertEqual(try count(fromToolResult: searchResult), 1)

        let updateResult = try await MemoryUpdateTool(memoryManager: manager).execute(
            call: ToolCall(
                id: "call_update",
                toolID: "memory_update",
                arguments: [
                    "id": .string(memoryID.uuidString),
                    "text": .string("User prefers concise answers in Chinese.")
                ]
            ),
            context: context
        )

        XCTAssertFalse(updateResult.isError)

        let listResult = try await MemoryListTool(memoryManager: manager).execute(
            call: ToolCall(
                id: "call_list",
                toolID: "memory_list",
                arguments: [:]
            ),
            context: context
        )

        XCTAssertEqual(try count(fromToolResult: listResult), 1)
        XCTAssertTrue(listResult.content.contains("concise answers in Chinese"))

        let deleteResult = try await MemoryDeleteTool(memoryManager: manager).execute(
            call: ToolCall(
                id: "call_delete",
                toolID: "memory_delete",
                arguments: ["id": .string(memoryID.uuidString)]
            ),
            context: context
        )

        XCTAssertFalse(deleteResult.isError)

        memories = try await manager.savedMemories(scope: .user)
        XCTAssertTrue(memories.isEmpty)
    }

    func testMemoryAddToolRejectsEmptyText() async throws {
        let manager = MemoryManager(
            store: UserDefaultsMemoryStore(
                defaults: defaults,
                storageKey: "invalidMemoryTools"
            )
        )

        let result = try await MemoryAddTool(memoryManager: manager).execute(
            call: ToolCall(
                id: "call_add",
                toolID: "memory_add",
                arguments: ["text": .string("   ")]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertTrue(result.isError)
        let memories = try await manager.savedMemories(scope: .user)
        XCTAssertTrue(memories.isEmpty)
    }

    func testMemorySearchToolRejectsInvalidLimit() async throws {
        let manager = MemoryManager(
            store: UserDefaultsMemoryStore(
                defaults: defaults,
                storageKey: "invalidMemoryToolLimit"
            )
        )

        let result = try await MemorySearchTool(memoryManager: manager).execute(
            call: ToolCall(
                id: "call_search",
                toolID: "memory_search",
                arguments: [
                    "query": .string("concise"),
                    "limit": .string("many")
                ]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("limit"))
    }

    private func count(fromToolResult result: ToolResult) throws -> Int {
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(payload["count"] as? Int)
    }
}
