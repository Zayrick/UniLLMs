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

        let fullRange = NSRange(location: 0, length: attributedString.length)
        var updates: [(positions: [CGFloat], range: NSRange)] = []
        attributedString.enumerateAttribute(.chatBlockQuoteBarPositions, in: fullRange) { value, range, _ in
            let existingPositions = (value as? [CGFloat]) ?? []
            let positions = blockQuoteBarPositions(
                adding: ChatMarkdownBlockQuoteStyle.barLeading,
                to: existingPositions
            )
            updates.append((positions, range))
        }

        for update in updates {
            attributedString.addAttribute(
                .chatBlockQuoteBarPositions,
                value: update.positions,
                range: update.range
            )
        }
    }

    private func blockQuoteBarPositions(
        adding position: CGFloat,
        to existingPositions: [CGFloat]
    ) -> [CGFloat] {
        var result = existingPositions
        if !result.contains(position) {
            result.append(position)
        }
        return result.sorted()
    }
}
