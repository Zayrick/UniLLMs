//
//  BuiltInToolCatalog.swift
//  UniLLMs
//
//  Owns concrete built-in tool registration.
//  Created by Codex on 2026/5/16.
//

import Foundation

enum BuiltInToolCatalog {
    static func makeRegistry() -> ToolRegistry {
        ToolRegistry(
            tools: [
                DateTimeTool()
            ]
        )
    }
}
