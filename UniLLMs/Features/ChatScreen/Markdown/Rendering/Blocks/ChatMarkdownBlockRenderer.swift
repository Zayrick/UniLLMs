//
//  ChatMarkdownBlockRenderer.swift
//  UniLLMs
//
//  Block-level Markdown dispatching.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

final class ChatMarkdownBlockRenderer {
    private let context: ChatMarkdownRenderingContext
    private let inlineRenderer: ChatMarkdownInlineRenderer
    private lazy var leafBlockRenderer = ChatMarkdownLeafBlockRenderer(
        context: context,
        inlineRenderer: inlineRenderer
    )
    private lazy var listRenderer = ChatMarkdownListRenderer(
        context: context,
        inlineRenderer: inlineRenderer,
        renderBlock: { [unowned self] markup in
            self.renderBlock(markup)
        }
    )
    private lazy var quoteRenderer = ChatMarkdownBlockQuoteRenderer(
        context: context,
        renderChildBlocks: { [unowned self] children in
            self.renderChildBlocks(children)
        }
    )
    private lazy var tableRenderer = ChatMarkdownTableRenderer(
        context: context,
        inlineRenderer: inlineRenderer
    )

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
        inlineRenderer = ChatMarkdownInlineRenderer(context: context)
    }

    func renderBlock(_ markup: any Markup) -> NSMutableAttributedString {
        switch markup {
        case let heading as Heading:
            return leafBlockRenderer.renderHeading(heading)
        case let paragraph as Paragraph:
            return leafBlockRenderer.renderParagraph(paragraph)
        case let unorderedList as UnorderedList:
            return listRenderer.renderUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            return listRenderer.renderOrderedList(orderedList)
        case let codeBlock as CodeBlock:
            return leafBlockRenderer.renderCodeBlock(codeBlock)
        case let quote as BlockQuote:
            return quoteRenderer.render(quote)
        case let table as Table:
            return tableRenderer.renderPlainText(table)
        case _ as ThematicBreak:
            return leafBlockRenderer.renderThematicBreak()
        case let htmlBlock as HTMLBlock:
            return leafBlockRenderer.renderHTMLBlock(htmlBlock)
        case let image as Markdown.Image:
            return leafBlockRenderer.renderImage(image)
        default:
            let result = NSMutableAttributedString()
            for child in markup.children {
                result.append(renderBlock(child))
            }
            return result
        }
    }

    func renderTableData(_ table: Table) -> ChatMarkdownTableData {
        tableRenderer.renderData(table)
    }

    private func renderChildBlocks(_ children: MarkupChildren) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            result.append(renderBlock(child))
        }
        return result
    }
}
