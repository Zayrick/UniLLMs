//
//  BuiltInToolCatalog.swift
//  UniLLMs
//
//  Owns concrete built-in tool registration.
//  Created by Zayrick on 2026/5/16.
//

import Foundation

enum BuiltInToolCatalog {
    static func makeRegistry(memoryManager: MemoryManager) -> ToolRegistry {
        ToolRegistry(
            tools: [
                DateTimeTool(),
                CalendarCreateTool(),
                CalendarReadTool(),
                CalendarUpdateTool(),
                CalendarDeleteTool(),
                MemoryAddTool(memoryManager: memoryManager),
                MemoryDeleteTool(memoryManager: memoryManager),
                MemoryListTool(memoryManager: memoryManager),
                MemorySearchTool(memoryManager: memoryManager),
                MemoryUpdateTool(memoryManager: memoryManager)
            ]
        )
    }
}
