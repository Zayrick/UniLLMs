//
//  OpenAIChatPromptRendererTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class OpenAIChatPromptRendererTests: XCTestCase {
    func testRendererCombinesSystemPromptAndMemoriesIntoSingleSystemMessage() {
        let prompt = SystemPromptRecord(
            title: "Translator",
            content: "Always answer in Chinese.",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let memories = [
            MemoryRecord(
                scope: .user,
                text: "Use metric units.",
                createdAt: Date(timeIntervalSince1970: 20)
            ),
            MemoryRecord(
                scope: .user,
                text: "Prefer short answers.",
                createdAt: Date(timeIntervalSince1970: 30)
            )
        ]

        let messages = OpenAIChatPromptRenderer.messages(
            for: ChatRequest(
                modelID: "test-model",
                messages: [ChatMessage(role: .user, content: "Hello")],
                context: ChatContext(systemPrompt: prompt, memories: memories)
            ),
            supportsFileAttachments: false
        )

        XCTAssertEqual(messages.map(\.role), [.system, .user])
        XCTAssertEqual(
            messages.first?.content,
            .text("Always answer in Chinese.\n\nMemory: Use metric units.\n\nMemory: Prefer short answers.")
        )
        XCTAssertEqual(messages.dropFirst().first?.content, .text("Hello"))
    }

    func testRendererDoesNotDuplicateInstructionsAcrossToolLoopMessages() {
        let prompt = SystemPromptRecord(
            title: "Tools",
            content: "Use tools when needed."
        )
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "lookup",
            arguments: "{}"
        )

        let messages = OpenAIChatPromptRenderer.messages(
            for: ChatRequest(
                modelID: "test-model",
                messages: [
                    ChatMessage(role: .user, content: "Search"),
                    ChatMessage(role: .assistant, content: "", toolCalls: [toolCall]),
                    ChatMessage(role: .tool, content: "Result", toolCallID: "call_1")
                ],
                context: ChatContext(systemPrompt: prompt)
            ),
            supportsFileAttachments: false
        )

        XCTAssertEqual(messages.map(\.role), [.system, .user, .assistant, .tool])
        XCTAssertEqual(messages.filter { $0.role == .system }.count, 1)
        XCTAssertEqual(messages[2].toolCalls?.first?.id, "call_1")
        XCTAssertNil(messages[2].content)
        XCTAssertEqual(messages[3].toolCallID, "call_1")
    }

    func testRendererOmitsBlankSystemPromptAndBlankMemories() {
        let prompt = SystemPromptRecord(
            title: "Blank",
            content: " \n "
        )
        let memory = MemoryRecord(
            scope: .user,
            text: " \n "
        )

        let messages = OpenAIChatPromptRenderer.messages(
            for: ChatRequest(
                modelID: "test-model",
                messages: [ChatMessage(role: .user, content: "Hello")],
                context: ChatContext(systemPrompt: prompt, memories: [memory])
            ),
            supportsFileAttachments: false
        )

        XCTAssertEqual(messages.map(\.role), [.user])
        XCTAssertEqual(messages.first?.content, .text("Hello"))
    }
}
