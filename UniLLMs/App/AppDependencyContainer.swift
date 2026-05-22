//
//  AppDependencyContainer.swift
//  UniLLMs
//
//  Assembles the default service graph for App, Chat, Provider, Tools, System Prompts, MCP, Memory, and Archive modules.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class AppDependencyContainer {
    let coreDataStack: CoreDataStack
    let providerRegistry: LLMsProviderRegistry
    let providerStore: LLMsProviderStore
    let providerManager: LLMsProviderManager
    let toolRegistry: ToolRegistry
    let toolSettingsStore: any ToolSettingsStore
    let toolSettingsManager: ToolSettingsManager
    let toolCatalog: ToolCatalog
    let toolManager: ToolManager
    let systemPromptManager: SystemPromptManager
    let memoryManager: MemoryManager
    let chatHistoryStore: UserDefaultsChatStore
    let chatRuntime: ChatRuntime
    let mcpServerManager: MCPServerManager
    let archiveStore: ArchiveStore

    init(
        coreDataStack: CoreDataStack = CoreDataStack(),
        providerStore: LLMsProviderStore = .shared,
        systemPromptStore: any SystemPromptStore = UserDefaultsSystemPromptStore.shared
    ) {
        self.coreDataStack = coreDataStack
        self.providerStore = providerStore

        providerRegistry = LLMsProviderCatalog.makeRegistry()
        providerManager = LLMsProviderManager(
            registry: providerRegistry,
            store: providerStore
        )

        let toolRegistry = BuiltInToolCatalog.makeRegistry()
        self.toolRegistry = toolRegistry
        let toolSettingsStore = UserDefaultsToolSettingsStore.shared
        // Preserve the previous MCP-owned global switch before MCP configuration is next saved.
        _ = toolSettingsStore.loadToolsEnabled()
        self.toolSettingsStore = toolSettingsStore
        let toolSettingsManager = ToolSettingsManager(
            registry: toolRegistry,
            store: toolSettingsStore
        )
        self.toolSettingsManager = toolSettingsManager
        systemPromptManager = SystemPromptManager(store: systemPromptStore)
        memoryManager = MemoryManager()
        chatHistoryStore = UserDefaultsChatStore()
        let mcpServerManager = MCPServerManager()
        self.mcpServerManager = mcpServerManager
        toolCatalog = ToolCatalog(
            registry: toolRegistry,
            isEnabled: { toolSettingsManager.isToolsEnabled },
            isRegisteredToolEnabled: { toolSettingsManager.isBuiltInToolEnabled(id: $0) },
            dynamicSources: [mcpServerManager]
        )
        toolManager = ToolManager(catalog: toolCatalog)
        archiveStore = InMemoryArchiveStore()

        let contextBuilder = ChatContextBuilder(
            memoryManager: memoryManager,
            toolCatalog: toolCatalog
        )
        let responseStreamer = ChatResponseStreamer(providerManager: providerManager)
        let turnRunner = ChatTurnRunner(
            responseStreamer: responseStreamer,
            toolManager: toolManager
        )
        chatRuntime = ChatRuntime(
            providerStore: providerStore,
            providerManager: providerManager,
            systemPromptManager: systemPromptManager,
            contextBuilder: contextBuilder,
            turnRunner: turnRunner,
            historyStore: chatHistoryStore
        )
    }
}
