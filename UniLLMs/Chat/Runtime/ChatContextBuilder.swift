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
    private let toolCatalog: ToolCatalog

    init(
        memoryManager: MemoryManager,
        toolCatalog: ToolCatalog
    ) {
        self.memoryManager = memoryManager
        self.toolCatalog = toolCatalog
    }

    func buildContext(
        session: ChatSession?,
        messages: [ChatMessage],
        includeTools: Bool
    ) async -> ChatContext {
        let availableTools = includeTools ? await toolCatalog.loadAvailableTools() : []
        let baseContext = ChatContext(
            session: session,
            messages: messages,
            memories: [],
            availableTools: availableTools
        )
        let memories = (try? await memoryManager.retrieveRelevantMemories(for: baseContext)) ?? []
        return ChatContext(
            session: session,
            messages: messages,
            memories: memories,
            availableTools: availableTools
        )
    }
}
