//
//  ChatPromptAssemblerTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatPromptAssemblerTests: XCTestCase {
    func testAssemblePromptKeepsInstructionsSeparateFromMessages() {
        let memoryDate = Date(timeIntervalSince1970: 100)
        let messageDate = Date(timeIntervalSince1970: 200)
        let promptDate = Date(timeIntervalSince1970: 50)
        let prompt = makePrompt(
            title: "Translator",
            content: "Always answer in Chinese.",
            updatedAt: promptDate
        )
        let context = ChatContext(
            messages: [
                makeTestChatMessage(role: .user, content: "Hello", createdAt: messageDate)
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
        XCTAssertYAMLEncodedMemories(promptParts.instructions[1].content, contains: ["Use metric units."])
        XCTAssertEqual(promptParts.instructions[1].createdAt, memoryDate)
        XCTAssertEqual(promptParts.messages.map(\.role), [.user])
        XCTAssertEqual(promptParts.messages[0].content, "Hello")
        XCTAssertEqual(promptParts.messages[0].createdAt, messageDate)
    }

    func testAssemblePromptKeepsOriginalMessagesWhenInstructionsAreEmpty() {
        let originalMessages = [
            makeTestChatMessage(role: .system, content: "Be concise."),
            makeTestChatMessage(role: .user, content: "Summarize this.")
        ]

        let prompt = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(messages: originalMessages)
        )

        XCTAssertTrue(prompt.instructions.isEmpty)
        XCTAssertEqual(prompt.messages, originalMessages)
    }

    func testInstructionTextCombinesSystemPromptAndMemories() {
        let originalMessages = [
            makeTestChatMessage(role: .user, content: "Hello")
        ]
        let prompt = makePrompt(
            title: "Translator",
            content: "Always answer in Chinese."
        )
        let memory = makeMemory(text: "Use metric units.")

        let promptParts = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(
                messages: originalMessages,
                systemPrompt: prompt,
                memories: [memory]
            )
        )

        let memoryInstruction = promptParts.instructions.first { $0.kind == .memory }
        XCTAssertEqual(promptParts.instructionText, "Always answer in Chinese.\n\n\(memoryInstruction?.content ?? "")")
        XCTAssertEqual(promptParts.messages, originalMessages)
    }

    func testInstructionTextCombinesSystemPromptCurrentDateAndMemories() {
        let currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        let prompt = makePrompt(
            title: "Translator",
            content: "Always answer in Chinese."
        )
        let memory = makeMemory(text: "Use metric units.")

        let promptParts = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(
                systemPrompt: prompt,
                currentDate: currentDate,
                memories: [memory]
            )
        )

        XCTAssertEqual(promptParts.instructions.map(\.kind), [.systemPrompt, .currentDate, .memory])
        let currentDateInstruction = promptParts.instructions[1]
        XCTAssertEqual(currentDateInstruction.createdAt, currentDate)
        XCTAssertTrue(currentDateInstruction.content.hasPrefix("current_datetime: "))
        XCTAssertTrue(promptParts.instructionText?.contains("\n\ncurrent_datetime: ") == true)
    }

    func testMemoryInstructionFormatsMultipleMemoriesAsYAMLLikeArray() {
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)
        let promptParts = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(
                memories: [
                    MemoryRecord(scope: .user, text: "Use metric units.", createdAt: olderDate),
                    MemoryRecord(scope: .user, text: "Prefer short answers.", createdAt: newerDate)
                ]
            )
        )

        XCTAssertEqual(promptParts.instructions.map(\.kind), [.memory])
        XCTAssertYAMLEncodedMemories(
            promptParts.instructionText,
            contains: ["Use metric units.", "Prefer short answers."]
        )
        XCTAssertEqual(promptParts.instructions.first?.createdAt, newerDate)
    }

    func testMemoryInstructionFormatsMultilineMemoryWithYAMLEncoder() {
        let promptParts = ChatPromptAssembler().assemblePrompt(
            from: ChatContext(
                memories: [
                    makeMemory(text: "Line one\nLine two")
                ]
            )
        )

        XCTAssertYAMLEncodedMemories(promptParts.instructionText, contains: ["Line one", "Line two"])
    }

    func testMemoryInstructionUsesFallbackWhenEncoderFails() {
        let promptParts = ChatPromptAssembler(
            memoryInstructionFormatter: ChatMemoryInstructionFormatter(
                encoder: FailingChatMemoryInstructionEncoder()
            )
        ).assemblePrompt(
            from: ChatContext(
                memories: [
                    makeMemory(text: "Line one\nLine two")
                ]
            )
        )

        XCTAssertEqual(promptParts.instructions.map(\.kind), [.memory])
        XCTAssertEqual(
            promptParts.instructionText,
            """
            memories:
            - |-
              Line one
              Line two
            """
        )
    }

    func testAssemblePromptOmitsBlankSystemPromptAndMemory() {
        let originalMessages = [
            makeTestChatMessage(role: .user, content: "Hello")
        ]
        let prompt = makePrompt(
            title: "Blank",
            content: " \n\t "
        )
        let memory = makeMemory(text: " \n\t ")

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

private struct FailingChatMemoryInstructionEncoder: ChatMemoryInstructionEncoding {
    func encodeMemories(_ memories: [String]) throws -> String {
        throw FailingChatMemoryInstructionEncoderError.failed
    }
}

private enum FailingChatMemoryInstructionEncoderError: Error {
    case failed
}

private func makePrompt(
    title: String,
    content: String,
    createdAt: Date = Date(timeIntervalSince1970: 1),
    updatedAt: Date = Date(timeIntervalSince1970: 1)
) -> SystemPromptRecord {
    SystemPromptRecord(
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
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

private func XCTAssertYAMLEncodedMemories(
    _ content: String?,
    contains expectedMemories: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let content else {
        XCTFail("Expected memory YAML content.", file: file, line: line)
        return
    }

    XCTAssertTrue(content.hasPrefix("memories:\n"), file: file, line: line)
    XCTAssertTrue(content.contains("\n-"), file: file, line: line)
    for memory in expectedMemories {
        XCTAssertTrue(content.contains(memory), file: file, line: line)
    }
}
