//
//  ChatMarkdownRenderer.swift
//  UniLLMs
//
//  Renders chat Markdown into attributed text and block views using swift-markdown.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

enum ChatMarkdownRenderedBlock {
    case text(NSAttributedString)
    case table(ChatMarkdownTableData)
}

struct ChatMarkdownRenderer {
    private static let parseLock = NSLock()

    let style: ChatMarkdownRenderStyle
    let traitCollection: UITraitCollection
    let listState = ChatMarkdownListState()
    let quoteState = ChatMarkdownQuoteState()

    init(style: ChatMarkdownRenderStyle = .assistant, traitCollection: UITraitCollection) {
        self.style = style
        self.traitCollection = traitCollection
    }

    mutating func render(markdown: String) -> NSAttributedString {
        guard !markdown.isEmpty else {
            return NSAttributedString()
        }

        let blocks = renderBlocks(markdown: markdown)
        let result = NSMutableAttributedString()
        for block in blocks {
            switch block {
            case let .text(text):
                result.append(text)
            case let .table(tableData):
                result.append(renderPlainTextTable(tableData))
            }
        }

        trimTrailingNewlines(in: result)
        return result
    }

    mutating func renderBlocks(markdown: String) -> [ChatMarkdownRenderedBlock] {
        guard !markdown.isEmpty else {
            return []
        }

        let document = Self.parseDocument(markdown)
        var blocks: [ChatMarkdownRenderedBlock] = []
        let result = NSMutableAttributedString()

        for child in document.children {
            if let table = child as? Table {
                flushTextBlock(result, to: &blocks)
                let tableData = renderTableData(table)
                if !tableData.isEmpty {
                    blocks.append(.table(tableData))
                }
            } else {
                result.append(renderBlock(child))
            }
        }

        trimTrailingNewlines(in: result)
        flushTextBlock(result, to: &blocks)
        return blocks
    }

    private static func parseDocument(_ markdown: String) -> Document {
        parseLock.lock()
        defer { parseLock.unlock() }
        return Document(parsing: markdown)
    }

    private func flushTextBlock(
        _ attributedString: NSMutableAttributedString,
        to blocks: inout [ChatMarkdownRenderedBlock]
    ) {
        guard attributedString.length > 0 else {
            return
        }

        blocks.append(.text(NSAttributedString(attributedString: attributedString)))
        attributedString.deleteCharacters(in: NSRange(location: 0, length: attributedString.length))
    }
}
