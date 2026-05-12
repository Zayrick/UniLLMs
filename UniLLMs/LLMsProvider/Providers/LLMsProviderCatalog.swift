//
//  LLMsProviderCatalog.swift
//  UniLLMs
//
//  Owns concrete LLM provider registration.
//  Created by Codex on 2026/5/12.
//

import Foundation

enum LLMsProviderCatalog {
    static func makeRegistry() -> LLMsProviderRegistry {
        LLMsProviderRegistry(
            adapters: [
                OpenRouterProvider(),
                OpenAICompatibleProvider()
            ]
        )
    }
}
