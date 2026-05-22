//
//  OpenAIChatPromptRenderer.swift
//  UniLLMs
//
//  Renders provider-neutral chat prompt context into OpenAI Chat Completions messages.
//
//  Created by Zayrick on 2026/5/22.
//

import Foundation

nonisolated enum OpenAIChatPromptRenderer {
    static func messages(
        for request: ChatRequest,
        supportsFileAttachments: Bool
    ) -> [OpenRouterChatMessage] {
        let prompt = ChatPromptAssembler().assemblePrompt(from: request)
        return messages(for: prompt).map {
            OpenRouterChatMessage(
                message: $0,
                supportsFileAttachments: supportsFileAttachments
            )
        }
    }

    private static func messages(for prompt: ChatPrompt) -> [ChatMessage] {
        guard let instructionText = prompt.instructionText else {
            return prompt.messages
        }

        let instructionMessage = ChatMessage(
            role: .system,
            content: instructionText,
            createdAt: prompt.instructions.first?.createdAt ?? Date()
        )
        return [instructionMessage] + prompt.messages
    }
}
