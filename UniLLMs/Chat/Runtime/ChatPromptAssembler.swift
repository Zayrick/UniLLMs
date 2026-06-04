//
//  ChatPromptAssembler.swift
//  UniLLMs
//
//  Builds provider-neutral prompt instructions from chat context.
//  Created by Zayrick on 2026/5/11.
//

import Foundation
import Yams

nonisolated struct ChatInstruction: Equatable {
    nonisolated enum Kind: Equatable {
        case systemPrompt
        case currentDate
        case memory
    }

    var kind: Kind
    var content: String
    var createdAt: Date
}

nonisolated struct ChatPrompt: Equatable {
    var instructions: [ChatInstruction]
    var messages: [ChatMessage]

    var instructionText: String? {
        let text = instructions
            .map(\.content)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

nonisolated struct ChatPromptAssembler {
    private struct MemoryInstructionPayload: Encodable {
        var memories: [String]
    }

    private struct IncludedMemory {
        var text: String
        var createdAt: Date
    }

    nonisolated func assemblePrompt(from request: ChatRequest) -> ChatPrompt {
        assemblePrompt(from: request.context, messages: request.messages)
    }

    nonisolated func assemblePrompt(from context: ChatContext) -> ChatPrompt {
        assemblePrompt(from: context, messages: context.messages)
    }

    nonisolated func assemblePrompt(
        from context: ChatContext,
        messages: [ChatMessage]
    ) -> ChatPrompt {
        ChatPrompt(
            instructions: Self.instructions(from: context),
            messages: messages
        )
    }

    nonisolated private static func instructions(from context: ChatContext) -> [ChatInstruction] {
        var instructions: [ChatInstruction] = []
        if let instruction = systemPromptInstruction(from: context.systemPrompt) {
            instructions.append(instruction)
        }
        if let instruction = currentDateInstruction(from: context.currentDate) {
            instructions.append(instruction)
        }
        if let instruction = memoryInstruction(from: context.memories) {
            instructions.append(instruction)
        }
        return instructions
    }

    nonisolated private static func systemPromptInstruction(from prompt: SystemPromptRecord?) -> ChatInstruction? {
        guard let prompt else {
            return nil
        }

        let content = prompt.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return nil
        }

        return ChatInstruction(
            kind: .systemPrompt,
            content: content,
            createdAt: prompt.updatedAt
        )
    }

    nonisolated private static func currentDateInstruction(from currentDate: Date?) -> ChatInstruction? {
        guard let currentDate else {
            return nil
        }

        return ChatInstruction(
            kind: .currentDate,
            content: currentDateInstructionContent(from: currentDate),
            createdAt: currentDate
        )
    }

    nonisolated private static func memoryInstruction(from memories: [MemoryRecord]) -> ChatInstruction? {
        let includedMemories = memories.compactMap(includedMemory(from:))
        guard !includedMemories.isEmpty,
              let content = try? memoryInstructionContent(from: includedMemories) else {
            return nil
        }

        return ChatInstruction(
            kind: .memory,
            content: content,
            createdAt: latestCreatedAt(from: includedMemories)
        )
    }

    nonisolated private static func includedMemory(from memory: MemoryRecord) -> IncludedMemory? {
        let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        return IncludedMemory(
            text: text,
            createdAt: memory.createdAt
        )
    }

    nonisolated private static func currentDateInstructionContent(from currentDate: Date) -> String {
        let formattedDate = ISO8601DateFormatter.string(
            from: currentDate,
            timeZone: .current,
            formatOptions: [.withInternetDateTime, .withColonSeparatorInTimeZone]
        )
        return "current_datetime: \(formattedDate)"
    }

    nonisolated private static func memoryInstructionContent(from memories: [IncludedMemory]) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.allowUnicode = true
        let payload = MemoryInstructionPayload(memories: memories.map(\.text))
        return try encoder.encode(payload)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func latestCreatedAt(from memories: [IncludedMemory]) -> Date {
        memories.map(\.createdAt).max() ?? Date(timeIntervalSince1970: 0)
    }
}
