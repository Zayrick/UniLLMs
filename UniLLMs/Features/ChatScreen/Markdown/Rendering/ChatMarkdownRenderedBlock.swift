//
//  ChatMarkdownRenderedBlock.swift
//  UniLLMs
//
//  Rendered Markdown block values consumed by chat presentation views.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

nonisolated struct ChatMarkdownImageBlock: Equatable {
    let source: String
    let altText: String
}

nonisolated struct ChatMarkdownCodeBlock: Equatable {
    let code: String
    let language: String?
    let isStreaming: Bool

    nonisolated init(code: String, language: String?, isStreaming: Bool = false) {
        self.code = code
        self.language = language
        self.isStreaming = isStreaming
    }

    var displayLanguage: String {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else {
            return String(localized: .markdownCode)
        }

        return language
    }
}

nonisolated struct ChatMarkdownDetailsBlock {
    let summary: String
    let isOpen: Bool
    let children: [ChatMarkdownRenderedBlock]
}

nonisolated struct ChatMarkdownBlockQuoteBlock {
    let children: [ChatMarkdownRenderedBlock]
}

nonisolated enum ChatMarkdownListMarker: Equatable {
    case text(String)
    case checkbox(isChecked: Bool)
}

nonisolated struct ChatMarkdownListItemBlock {
    let marker: ChatMarkdownListMarker
    let children: [ChatMarkdownRenderedBlock]
}

nonisolated struct ChatMarkdownListBlock {
    let isOrdered: Bool
    let items: [ChatMarkdownListItemBlock]
}

nonisolated enum ChatMarkdownRenderedBlock {
    case text(NSAttributedString)
    case codeBlock(ChatMarkdownCodeBlock)
    case mathBlock(ChatMarkdownMathBlock)
    case table(ChatMarkdownTableData)
    case image(ChatMarkdownImageBlock)
    case details(ChatMarkdownDetailsBlock)
    case blockQuote(ChatMarkdownBlockQuoteBlock)
    case list(ChatMarkdownListBlock)
}
