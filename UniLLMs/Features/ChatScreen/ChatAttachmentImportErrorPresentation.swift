//
//  ChatAttachmentImportErrorPresentation.swift
//  UniLLMs
//
//  Converts attachment import failures into a single user-presentable message.
//  Created by Codex on 2026/6/5.
//

import Foundation

struct ChatAttachmentImportErrorPresentation {
    let message: String

    static func make(for errors: [Error]) -> ChatAttachmentImportErrorPresentation? {
        let message = errors
            .map(\.localizedDescription)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !message.isEmpty else {
            return nil
        }

        return ChatAttachmentImportErrorPresentation(message: message)
    }
}
