//
//  ChatPromptAssembler.swift
//  UniLLMs
//
//  Converts ChatContext into provider-facing messages and isolates prompt assembly policy.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

struct ChatPromptAssembler {
    func assembleMessages(from context: ChatContext) -> [ChatMessage] {
        let memoryMessages = context.memories.map {
            ChatMessage(
                role: .system,
                content: "Memory: \($0.text)",
                createdAt: $0.createdAt
            )
        }
        return memoryMessages + context.messages
    }
}
