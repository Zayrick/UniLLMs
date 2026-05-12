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
    let toolManager: ToolManager
    let memoryManager: MemoryManager
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
        toolManager = ToolManager(registry: toolRegistry)
        memoryManager = MemoryManager()
        mcpServerManager = MCPServerManager()
        archiveStore = InMemoryArchiveStore()

        let contextBuilder = ChatContextBuilder(
            memoryManager: memoryManager,
            toolRegistry: toolRegistry
        )
        let responseStreamer = ChatResponseStreamer(providerManager: providerManager)
        let turnRunner = ChatTurnRunner(responseStreamer: responseStreamer)
        chatRuntime = ChatRuntime(
            providerStore: providerStore,
            providerManager: providerManager,
            contextBuilder: contextBuilder,
            turnRunner: turnRunner
        )
    }
}
