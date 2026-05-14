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
        let htmlTableRenderer = ChatMarkdownHTMLTableRenderer(context: context)
        return renderBlocks(
            from: Array(document.children),
            context: context,
            blockRenderer: blockRenderer,
            htmlTableRenderer: htmlTableRenderer
        )
    }

    private func renderBlocks(
        from children: [any Markup],
        context: ChatMarkdownRenderingContext,
        blockRenderer: ChatMarkdownBlockRenderer,
        htmlTableRenderer: ChatMarkdownHTMLTableRenderer
    ) -> [ChatMarkdownRenderedBlock] {
        var blocks: [ChatMarkdownRenderedBlock] = []
        let result = NSMutableAttributedString()
        var index = 0

        while index < children.count {
            let child = children[index]
            if let table = child as? Table {
                flushTextBlock(result, to: &blocks)
                let tableData = blockRenderer.renderTableData(table)
                if !tableData.isEmpty {
                    blocks.append(.table(tableData))
                }
            } else if let detailsResult = detailsBlock(
                startingAt: index,
                in: children,
                context: context,
                blockRenderer: blockRenderer,
                htmlTableRenderer: htmlTableRenderer
            ) {
                flushTextBlock(result, to: &blocks)
                blocks.append(.details(detailsResult.block))
                index = detailsResult.nextIndex
                continue
            } else if let codeBlock = child as? CodeBlock {
                flushTextBlock(result, to: &blocks)
                blocks.append(.codeBlock(renderCodeBlock(codeBlock)))
            } else if let htmlBlock = child as? HTMLBlock,
                      let tableData = htmlTableRenderer.renderTableData(fromHTML: htmlBlock.rawHTML) {
                flushTextBlock(result, to: &blocks)
                blocks.append(.table(tableData))
            } else if let htmlBlock = child as? HTMLBlock,
                      let imageBlock = ChatMarkdownHTMLSupport.imageBlock(fromHTML: htmlBlock.rawHTML) {
                flushTextBlock(result, to: &blocks)
                blocks.append(.image(imageBlock))
            } else if let imageBlock = standaloneImageBlock(from: child) {
                flushTextBlock(result, to: &blocks)
                blocks.append(.image(imageBlock))
            } else {
                result.append(blockRenderer.renderBlock(child))
            }

            index += 1
        }

        context.trimTrailingNewlines(in: result)
        flushTextBlock(result, to: &blocks)
        return blocks
    }

    private func renderCodeBlock(_ codeBlock: CodeBlock) -> ChatMarkdownCodeBlock {
        ChatMarkdownCodeBlock(
            code: codeBlock.code.trimmingCharacters(in: .newlines),
            language: codeBlock.language
        )
    }

    private static func parseDocument(_ markdown: String) -> Document {
        parseLock.lock()
        defer { parseLock.unlock() }
        return Document(parsing: markdown)
    }

    private func detailsBlock(
        startingAt index: Int,
        in children: [any Markup],
        context: ChatMarkdownRenderingContext,
        blockRenderer: ChatMarkdownBlockRenderer,
        htmlTableRenderer: ChatMarkdownHTMLTableRenderer
    ) -> (block: ChatMarkdownDetailsBlock, nextIndex: Int)? {
        guard let opening = detailsOpening(in: children[index]) else {
            return nil
        }

        var depth = opening.remainingDepth
        var pendingContent: [any Markup] = []
        var renderedChildren: [ChatMarkdownRenderedBlock] = []
        var currentIndex = index + 1

        func flushPendingContent() {
            guard !pendingContent.isEmpty else {
                return
            }

            renderedChildren.append(
                contentsOf: renderBlocks(
                    from: pendingContent,
                    context: context,
                    blockRenderer: blockRenderer,
                    htmlTableRenderer: htmlTableRenderer
                )
            )
            pendingContent.removeAll()
        }

        func appendRenderedMarkdownFragment(_ markdown: String) {
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            flushPendingContent()
            let document = Self.parseDocument(markdown)
            renderedChildren.append(
                contentsOf: renderBlocks(
                    from: Array(document.children),
                    context: context,
                    blockRenderer: blockRenderer,
                    htmlTableRenderer: htmlTableRenderer
                )
            )
        }

        appendRenderedMarkdownFragment(opening.bodyMarkdown)

        while currentIndex < children.count, depth > 0 {
            let child = children[currentIndex]

            if let htmlBlock = child as? HTMLBlock {
                let scan = ChatMarkdownHTMLSupport.markdownBeforeMatchingDetailsClosing(
                    inHTML: htmlBlock.rawHTML,
                    initialDepth: depth
                )
                if scan.didClose {
                    appendRenderedMarkdownFragment(scan.markdown)
                    currentIndex += 1
                    break
                }

                depth = scan.remainingDepth
                pendingContent.append(child)
                currentIndex += 1
                continue
            }

            pendingContent.append(child)
            currentIndex += 1
        }
        flushPendingContent()

        return (
            block: ChatMarkdownDetailsBlock(
                summary: opening.summary,
                isOpen: opening.isOpen,
                children: renderedChildren
            ),
            nextIndex: currentIndex
        )
    }

    private func detailsOpening(in markup: any Markup) -> ChatMarkdownDetailsOpening? {
        guard let htmlBlock = markup as? HTMLBlock else {
            return nil
        }

        return ChatMarkdownHTMLSupport.detailsOpening(fromHTML: htmlBlock.rawHTML)
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
              let onlyChild = visibleChildren.first else {
            return nil
        }

        if let image = onlyChild as? Markdown.Image {
            return imageBlock(from: image)
        }
        if let html = onlyChild as? InlineHTML {
            return ChatMarkdownHTMLSupport.imageBlock(fromHTML: html.rawHTML)
        }

        return nil
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
