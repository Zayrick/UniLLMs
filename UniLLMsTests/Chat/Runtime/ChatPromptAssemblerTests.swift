//
//  ChatPromptAssemblerTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatPromptAssemblerTests: XCTestCase {
    @MainActor
    func testAssemblePromptKeepsInstructionsSeparateFromMessages() {
        let memoryDate = Date(timeIntervalSince1970: 100)
        let messageDate = Date(timeIntervalSince1970: 200)
        let promptDate = Date(timeIntervalSince1970: 50)
        let prompt = SystemPromptRecord(
            title: "Translator",
            content: "Always answer in Chinese.",
            updatedAt: promptDate
        )
        let context = ChatContext(
            messages: [
                ChatMessage(role: .user, content: "Hello", createdAt: messageDate)
            ],
            systemPrompt: prompt,
            memories: [
                MemoryRecord(scope: .user, text: "Use metric units.", createdAt: memoryDate)
            ]
        )

        let promptParts = ChatPromptAssembler().assemblePrompt(from: context)

        XCTAssertEqual(promptParts.instructions.map(\.kind), [.systemPrompt, .memory])
        XCTAssertEqual(promptParts.instructions[0].content, "Always answer in Chinese.")
        XCTAssertEqual(promptParts.instructions[0].createdAt, promptDate)
        XCTAssertEqual(promptParts.instructions[1].content, "Memory: Use metric units.")
        XCTAssertEqual(promptParts.instructions[1].createdAt, memoryDate)
        XCTAssertEqual(promptParts.messages.map(\.role), [.user])
        XCTAssertEqual(promptParts.messages[0].content, "Hello")
        XCTAssertEqual(promptParts.messages[0].createdAt, messageDate)
    }

    @MainActor
    func testAssemblePromptKeepsOriginalMessagesWhenInstructionsAreEmpty() {
        let originalMessages = [
            ChatMessage(role: .system, content: "Be concise."),
            ChatMessage(role: .user, content: "Summarize this.")
        ]

        let prompt = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(messages: originalMessages)
        )

        XCTAssertTrue(prompt.instructions.isEmpty)
        XCTAssertEqual(prompt.messages, originalMessages)
    }

    @MainActor
    func testInstructionTextCombinesSystemPromptAndMemories() {
        let originalMessages = [
            ChatMessage(role: .user, content: "Hello")
        ]
        let prompt = SystemPromptRecord(
            title: "Translator",
            content: "Always answer in Chinese."
        )
        let memory = MemoryRecord(scope: .user, text: "Use metric units.")

        let promptParts = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(
                messages: originalMessages,
                systemPrompt: prompt,
                memories: [memory]
            )
        )

        XCTAssertEqual(promptParts.instructionText, "Always answer in Chinese.\n\nMemory: Use metric units.")
        XCTAssertEqual(promptParts.messages, originalMessages)
    }

    @MainActor
    func testAssemblePromptOmitsBlankSystemPromptAndMemory() {
        let originalMessages = [
            ChatMessage(role: .user, content: "Hello")
        ]
        let prompt = SystemPromptRecord(
            title: "Blank",
            content: " \n\t "
        )
        let memory = MemoryRecord(scope: .user, text: " \n\t ")

        let promptParts = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(
                messages: originalMessages,
                systemPrompt: prompt,
                memories: [memory]
            )
        )

        XCTAssertTrue(promptParts.instructions.isEmpty)
        XCTAssertNil(promptParts.instructionText)
        XCTAssertEqual(promptParts.messages, originalMessages)
    }
}
