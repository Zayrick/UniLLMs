//
//  ChatPromptAssembler.swift
//  UniLLMs
//
//  Builds provider-neutral prompt instructions from chat context.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct ChatInstruction: Equatable {
    nonisolated enum Kind: Equatable {
        case systemPrompt
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
        instructions.append(contentsOf: context.memories.compactMap(memoryInstruction(from:)))
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

    nonisolated private static func memoryInstruction(from memory: MemoryRecord) -> ChatInstruction? {
        let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        return ChatInstruction(
            kind: .memory,
            content: "Memory: \(text)",
            createdAt: memory.createdAt
        )
    }
}
