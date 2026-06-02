//
//  SystemPromptCore.swift
//  UniLLMs
//
//  Defines saved system prompts for future chat request assembly.
//  Created by Zayrick on 2026/5/19.
//

import Foundation

nonisolated struct SystemPromptRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? String(localized: .systemPromptsUntitledPrompt) : trimmedTitle
    }
}
