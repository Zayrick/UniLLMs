//
//  AppDependencyContainer.swift
//  UniLLMs
//
//  Assembles the default service graph for App, Chat, Provider, Tools, MCP, Memory, and Archive modules.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class AppDependencyContainer {
    let coreDataStack: CoreDataStack
    let providerRegistry: LLMsProviderRegistry
    let providerStore: LLMsProviderStore
    let providerManager: LLMsProviderManager
    let toolRegistry: ToolRegistry
    let toolCatalog: ToolCatalog
    let toolManager: ToolManager
    let memoryManager: MemoryManager
    let chatHistoryStore: UserDefaultsChatStore
    let chatRuntime: ChatRuntime
    let mcpServerManager: MCPServerManager
    let archiveStore: ArchiveStore

    init(
        coreDataStack: CoreDataStack = CoreDataStack(),
        providerStore: LLMsProviderStore = .shared
    ) {
        self.coreDataStack = coreDataStack
        self.providerStore = providerStore

        providerRegistry = LLMsProviderCatalog.makeRegistry()
        providerManager = LLMsProviderManager(
            registry: providerRegistry,
            store: providerStore
        )

        toolRegistry = ToolRegistry(
            tools: [
                DateTimeTool()
            ]
        )
        memoryManager = MemoryManager()
        chatHistoryStore = UserDefaultsChatStore()
        let mcpServerManager = MCPServerManager()
        self.mcpServerManager = mcpServerManager
        toolCatalog = ToolCatalog(
            registry: toolRegistry,
            isEnabled: { mcpServerManager.isToolsEnabled },
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
            contextBuilder: contextBuilder,
            turnRunner: turnRunner,
            historyStore: chatHistoryStore
        )
    }
}
