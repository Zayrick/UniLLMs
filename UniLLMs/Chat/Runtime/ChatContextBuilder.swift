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
    private let systemPromptSettingsStore: any SystemPromptSettingsStore
    private let clock: any AppClock
    private let buildPolicy: ChatContextBuildPolicy

    init(
        memoryManager: MemoryManager,
        toolCatalog: ToolCatalog,
        systemPromptSettingsStore: any SystemPromptSettingsStore = UserDefaultsSystemPromptSettingsStore.shared,
        clock: any AppClock = SystemAppClock(),
        buildPolicy: ChatContextBuildPolicy = ChatContextBuildPolicy()
    ) {
        self.memoryManager = memoryManager
        self.toolCatalog = toolCatalog
        self.systemPromptSettingsStore = systemPromptSettingsStore
        self.clock = clock
        self.buildPolicy = buildPolicy
    }

    func buildContext(
        session: ChatSession?,
        messages: [ChatMessage],
        systemPrompt: SystemPromptRecord?,
        includeTools: Bool
    ) async -> ChatContext {
        let availableTools = includeTools ? await toolCatalog.loadAvailableTools() : []
        let currentDate = systemPromptSettingsStore.loadInjectionSettings().isCurrentDateEnabled
            ? clock.now
            : nil
        let baseContext = ChatContext(
            session: session,
            messages: messages,
            systemPrompt: systemPrompt,
            currentDate: currentDate,
            memories: [],
            availableTools: availableTools
        )
        let memories = await buildPolicy.retrieveMemories(
            using: memoryManager,
            for: baseContext
        )
        return ChatContext(
            session: session,
            messages: messages,
            systemPrompt: systemPrompt,
            currentDate: currentDate,
            memories: memories,
            availableTools: availableTools
        )
    }
}
