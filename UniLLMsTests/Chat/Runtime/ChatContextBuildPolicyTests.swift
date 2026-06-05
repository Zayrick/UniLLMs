//
//  ChatContextBuildPolicyTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class ChatContextBuildPolicyTests: XCTestCase {
    func testRetrieveMemoriesReturnsRetrieverResult() async {
        let memory = makeMemory(text: "Use metric units.")
        let retriever = PolicyMemoryRetriever(result: [memory])
        let policy = ChatContextBuildPolicy()

        let memories = await policy.retrieveMemories(
            using: MemoryManager(retriever: retriever),
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "Units?")])
        )

        XCTAssertEqual(memories, [memory])
        XCTAssertEqual(retriever.capturedContexts.count, 1)
    }

    func testRetrieveMemoriesOmitMemoriesWhenRetrieverFails() async {
        let retriever = PolicyMemoryRetriever(error: PolicyMemoryError.failed)
        var failures: [ChatContextOptionalInputFailure.Source] = []
        let policy = ChatContextBuildPolicy { failure in
            failures.append(failure.source)
        }

        let memories = await policy.retrieveMemories(
            using: MemoryManager(retriever: retriever),
            for: ChatContext(messages: [makeTestChatMessage(role: .user, content: "Units?")])
        )

        XCTAssertTrue(memories.isEmpty)
        XCTAssertEqual(failures, [.memories])
        XCTAssertEqual(retriever.capturedContexts.count, 1)
    }
}

private final class PolicyMemoryRetriever: MemoryRetriever {
    private let result: [MemoryRecord]
    private let error: Error?
    private(set) var capturedContexts: [ChatContext] = []

    init(result: [MemoryRecord] = [], error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        capturedContexts.append(context)
        if let error {
            throw error
        }
        return result
    }
}

private enum PolicyMemoryError: Error {
    case failed
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
