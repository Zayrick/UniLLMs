//
//  ChatPromptAssemblerTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatPromptAssemblerTests: XCTestCase {
    func testAssembleMessagesPrependsMemoriesAsSystemMessages() {
        let memoryDate = Date(timeIntervalSince1970: 100)
        let messageDate = Date(timeIntervalSince1970: 200)
        let context = ChatContext(
            messages: [
                ChatMessage(role: .user, content: "Hello", createdAt: messageDate)
            ],
            memories: [
                MemoryRecord(scope: .user, text: "Use metric units.", createdAt: memoryDate)
            ]
        )

        let messages = ChatPromptAssembler().assembleMessages(from: context)

        XCTAssertEqual(messages.map(\.role), [.system, .user])
        XCTAssertEqual(messages[0].content, "Memory: Use metric units.")
        XCTAssertEqual(messages[0].createdAt, memoryDate)
        XCTAssertEqual(messages[1].content, "Hello")
        XCTAssertEqual(messages[1].createdAt, messageDate)
    }

    func testAssembleMessagesKeepsOriginalMessagesWhenMemoriesAreEmpty() {
        let originalMessages = [
            ChatMessage(role: .system, content: "Be concise."),
            ChatMessage(role: .user, content: "Summarize this.")
        ]

        let messages = ChatPromptAssembler().assembleMessages(
            from: ChatContext(messages: originalMessages)
        )

        XCTAssertEqual(messages, originalMessages)
    }
}
