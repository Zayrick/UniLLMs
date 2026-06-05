//
//  ChatSessionTitle.swift
//  UniLLMs
//
//  Creates a chat session title from the first user turn.
//

import Foundation

nonisolated enum ChatSessionTitle {
    static func make(
        prompt: String,
        attachments: [ChatAttachment] = [],
        emptyConversationTitle: String,
        attachmentFallbackTitle: String
    ) -> String {
        let collapsedPrompt = prompt
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !collapsedPrompt.isEmpty {
            return collapsedPrompt
        }

        if let first = attachments.first {
            let filename = first.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            return filename.isEmpty ? attachmentFallbackTitle : filename
        }

        return emptyConversationTitle
    }
}
