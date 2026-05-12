//
//  ChatMarkdownRenderer.swift
//  UniLLMs
//
//  Renders chat Markdown into attributed text using swift-markdown.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

struct ChatMarkdownRenderer {
    private static let parseLock = NSLock()

    let style: ChatMarkdownRenderStyle
    let traitCollection: UITraitCollection
    let listState = ChatMarkdownListState()

    init(style: ChatMarkdownRenderStyle = .assistant, traitCollection: UITraitCollection) {
        self.style = style
        self.traitCollection = traitCollection
    }

    mutating func render(markdown: String) -> NSAttributedString {
        guard !markdown.isEmpty else {
            return NSAttributedString()
        }

        let document = Self.parseDocument(markdown)
        let result = NSMutableAttributedString()

        for child in document.children {
            result.append(renderBlock(child))
        }

        trimTrailingNewlines(in: result)
        return result
    }

    private static func parseDocument(_ markdown: String) -> Document {
        parseLock.lock()
        defer { parseLock.unlock() }
        return Document(parsing: markdown)
    }
}
