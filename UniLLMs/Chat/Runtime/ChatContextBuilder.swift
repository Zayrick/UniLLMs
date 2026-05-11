//
//  ChatContextBuilder.swift
//  UniLLMs
//
//  Builds chat context for a turn by combining current messages, available tools, and retrievable memories.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class ChatContextBuilder {
    private let memoryManager: MemoryManager
    private let toolRegistry: ToolRegistry

    init(memoryManager: MemoryManager, toolRegistry: ToolRegistry) {
        self.memoryManager = memoryManager
        self.toolRegistry = toolRegistry
    }

    func buildContext(
        session: ChatSession?,
        messages: [ChatMessage]
    ) async -> ChatContext {
        let baseContext = ChatContext(
            session: session,
            messages: messages,
            memories: [],
            availableTools: toolRegistry.definitions
        )
        let memories = (try? await memoryManager.retrieveRelevantMemories(for: baseContext)) ?? []
        return ChatContext(
            session: session,
            messages: messages,
            memories: memories,
            availableTools: toolRegistry.definitions
        )
    }
}
