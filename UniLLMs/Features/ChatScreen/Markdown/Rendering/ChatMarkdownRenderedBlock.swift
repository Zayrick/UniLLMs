//
//  ChatMarkdownRenderedBlock.swift
//  UniLLMs
//
//  Rendered Markdown block values consumed by chat presentation views.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

struct ChatMarkdownImageBlock: Equatable {
    let source: String
    let altText: String
}

struct ChatMarkdownCodeBlock: Equatable {
    let code: String
    let language: String?
    /// True only when the source contains a real closing fence. Streaming code
    /// blocks keep their own open state instead of relying on a synthetic ``` tail.
    var isClosed: Bool = true

    var displayLanguage: String {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else {
            return "Code"
        }

        return language
    }
}

struct ChatMarkdownDetailsBlock {
    let summary: String
    let isOpen: Bool
    let children: [ChatMarkdownRenderedBlock]
}

enum ChatMarkdownRenderedBlock {
    case text(NSAttributedString)
    case codeBlock(ChatMarkdownCodeBlock)
    case mathBlock(ChatMarkdownMathBlock)
    case table(ChatMarkdownTableData)
    case image(ChatMarkdownImageBlock)
    case details(ChatMarkdownDetailsBlock)
}
