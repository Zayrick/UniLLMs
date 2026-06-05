//
//  BuiltInToolCatalog.swift
//  UniLLMs
//
//  Owns concrete built-in tool registration.
//  Created by Zayrick on 2026/5/16.
//

import Foundation

enum BuiltInToolCatalog {
    static func makeRegistry(
        memoryManager: MemoryManager,
        clock: any AppClock = SystemAppClock()
    ) -> ToolRegistry {
        ToolRegistry(
            tools: [
                DateTimeTool(clock: clock),
                MemoryAddTool(memoryManager: memoryManager),
                MemoryDeleteTool(memoryManager: memoryManager),
                MemoryListTool(memoryManager: memoryManager),
                MemorySearchTool(memoryManager: memoryManager),
                MemoryUpdateTool(memoryManager: memoryManager)
            ]
        )
    }
}
