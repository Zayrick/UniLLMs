//
//  ChatMarkdownBlockQuoteRenderer.swift
//  UniLLMs
//
//  Block quote Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import Markdown
import UIKit

private enum BlockQuoteLayout {
    static let indent: CGFloat = 12.0
    static let paragraphSpacing: CGFloat = 4.0
}

final class ChatMarkdownBlockQuoteRenderer {
    private let context: ChatMarkdownRenderingContext
    private let renderChildBlocks: (MarkupChildren) -> NSMutableAttributedString

    init(
        context: ChatMarkdownRenderingContext,
        renderChildBlocks: @escaping (MarkupChildren) -> NSMutableAttributedString
    ) {
        self.context = context
        self.renderChildBlocks = renderChildBlocks
    }

    func render(_ quote: BlockQuote) -> NSMutableAttributedString {
        context.pushBlockQuote()
        defer { context.popBlockQuote() }

        let result = renderChildBlocks(quote.children)

        context.trimTrailingNewlines(in: result)
        context.appendNewlineIfNeeded(to: result)
        applyBlockQuoteIndent(to: result)

        return result
    }

    private func applyBlockQuoteIndent(to attributedString: NSMutableAttributedString) {
        context.offsetParagraphIndent(
            in: attributedString,
            by: BlockQuoteLayout.indent,
            minimumParagraphSpacing: BlockQuoteLayout.paragraphSpacing
        )
    }
}
