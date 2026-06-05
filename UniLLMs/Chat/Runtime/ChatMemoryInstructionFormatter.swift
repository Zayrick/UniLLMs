//
//  ChatMemoryInstructionFormatter.swift
//  UniLLMs
//
//  Formats retrieved memories into a provider-neutral prompt instruction.
//  Created by Codex on 2026/6/5.
//

import Foundation
import Yams

nonisolated protocol ChatMemoryInstructionEncoding {
    func encodeMemories(_ memories: [String]) throws -> String
}

nonisolated struct ChatMemoryInstructionFormatter {
    private let encoder: any ChatMemoryInstructionEncoding

    init(encoder: any ChatMemoryInstructionEncoding = YAMLChatMemoryInstructionEncoder()) {
        self.encoder = encoder
    }

    func instructionContent(from memories: [String]) -> String {
        do {
            return try encoder.encodeMemories(memories)
        } catch {
            return Self.fallbackInstructionContent(from: memories)
        }
    }

    private static func fallbackInstructionContent(from memories: [String]) -> String {
        let memoryBlocks = memories.map { memory in
            "- |-\n\(indentedBlockScalar(memory))"
        }
        return (["memories:"] + memoryBlocks)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func indentedBlockScalar(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { "  \($0)" }
            .joined(separator: "\n")
    }
}

nonisolated private struct YAMLChatMemoryInstructionEncoder: ChatMemoryInstructionEncoding {
    private struct Payload: Encodable {
        var memories: [String]
    }

    func encodeMemories(_ memories: [String]) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.allowUnicode = true
        return try encoder.encode(Payload(memories: memories))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
