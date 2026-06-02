//
//  ChatMarkdownBlockQuoteRenderer.swift
//  UniLLMs
//
//  Block quote Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import Markdown
import UIKit

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
        let result = renderChildBlocks(quote.children)
        context.trimTrailingNewlines(in: result)

        applyBlockQuoteIndent(to: result)
        addBlockQuoteBar(to: result)

        context.appendNewlineIfNeeded(to: result)
        return result
    }

    private func applyBlockQuoteIndent(to attributedString: NSMutableAttributedString) {
        context.offsetParagraphIndent(
            in: attributedString,
            by: ChatMarkdownBlockQuoteStyle.indentPerLevel,
            minimumParagraphSpacing: context.style.blockQuoteParagraphSpacing(
                compatibleWith: context.traitCollection
            )
        )
    }

    private func addBlockQuoteBar(to attributedString: NSMutableAttributedString) {
        guard attributedString.length > 0 else {
            return
        }

        var location = 0
        while location < attributedString.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let existingPositions = (
                attributedString.attribute(
                    .chatBlockQuoteBarPositions,
                    at: location,
                    effectiveRange: &effectiveRange
                ) as? [CGFloat]
            ) ?? []
            let positions = ChatMarkdownBlockQuoteStyle.addingBarPosition(
                ChatMarkdownBlockQuoteStyle.barLeading,
                to: existingPositions
            )
            attributedString.addAttribute(
                .chatBlockQuoteBarPositions,
                value: positions,
                range: effectiveRange
            )
            location = effectiveRange.location + max(effectiveRange.length, 1)
        }
    }
}
