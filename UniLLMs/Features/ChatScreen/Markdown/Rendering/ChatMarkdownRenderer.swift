//
//  ChatMarkdownRenderer.swift
//  UniLLMs
//
//  Renders chat Markdown into presentation blocks using swift-markdown.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

struct ChatMarkdownRenderer {
    private static let parseLock = NSLock()

    let style: ChatMarkdownRenderStyle
    let traitCollection: UITraitCollection

    init(style: ChatMarkdownRenderStyle = .assistant, traitCollection: UITraitCollection) {
        self.style = style
        self.traitCollection = traitCollection
    }

    func render(markdown: String) -> [ChatMarkdownRenderedBlock] {
        guard !markdown.isEmpty else {
            return []
        }

        let document = Self.parseDocument(markdown)
        let context = ChatMarkdownRenderingContext(
            style: style,
            traitCollection: traitCollection
        )
        let blockRenderer = ChatMarkdownBlockRenderer(context: context)
        var blocks: [ChatMarkdownRenderedBlock] = []
        let result = NSMutableAttributedString()

        for child in document.children {
            if let table = child as? Table {
                flushTextBlock(result, to: &blocks)
                let tableData = blockRenderer.renderTableData(table)
                if !tableData.isEmpty {
                    blocks.append(.table(tableData))
                }
            } else if let imageBlock = standaloneImageBlock(from: child) {
                flushTextBlock(result, to: &blocks)
                blocks.append(.image(imageBlock))
            } else {
                result.append(blockRenderer.renderBlock(child))
            }
        }

        context.trimTrailingNewlines(in: result)
        flushTextBlock(result, to: &blocks)
        return blocks
    }

    private static func parseDocument(_ markdown: String) -> Document {
        parseLock.lock()
        defer { parseLock.unlock() }
        return Document(parsing: markdown)
    }

    private func standaloneImageBlock(from markup: any Markup) -> ChatMarkdownImageBlock? {
        if let image = markup as? Markdown.Image {
            return imageBlock(from: image)
        }

        guard let paragraph = markup as? Paragraph else {
            return nil
        }

        let visibleChildren = Array(paragraph.children).filter { !isIgnorableImageParagraphChild($0) }
        guard visibleChildren.count == 1,
              let image = visibleChildren.first as? Markdown.Image else {
            return nil
        }

        return imageBlock(from: image)
    }

    private func imageBlock(from image: Markdown.Image) -> ChatMarkdownImageBlock? {
        guard let source = image.source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return nil
        }

        return ChatMarkdownImageBlock(source: source, altText: image.plainText)
    }

    private func isIgnorableImageParagraphChild(_ markup: any Markup) -> Bool {
        if let text = markup as? Text {
            return text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return markup is SoftBreak || markup is LineBreak
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
