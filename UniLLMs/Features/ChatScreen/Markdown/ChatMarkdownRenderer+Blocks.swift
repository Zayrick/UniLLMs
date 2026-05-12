//
//  ChatMarkdownRenderer+Blocks.swift
//  UniLLMs
//
//  Block-level Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

private enum BlockQuoteLayout {
    static let indent: CGFloat = 12.0
    static let paragraphSpacing: CGFloat = 4.0
}

final class ChatMarkdownQuoteState {
    private(set) var depth = 0

    func push() {
        depth += 1
    }

    func pop() {
        depth = max(0, depth - 1)
    }
}

extension ChatMarkdownRenderer {
    private mutating func renderBlocks(_ children: MarkupChildren) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            result.append(renderBlock(child))
        }
        return result
    }

    mutating func renderBlock(_ markup: any Markup) -> NSMutableAttributedString {
        switch markup {
        case let heading as Heading:
            return renderHeading(heading)
        case let paragraph as Paragraph:
            return renderParagraph(paragraph)
        case let unorderedList as UnorderedList:
            return renderUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            return renderOrderedList(orderedList)
        case let codeBlock as CodeBlock:
            return renderCodeBlock(codeBlock)
        case let quote as BlockQuote:
            return renderBlockQuote(quote)
        case let table as Table:
            return renderTable(table)
        case _ as ThematicBreak:
            return renderThematicBreak()
        case let htmlBlock as HTMLBlock:
            return blockString(
                htmlBlock.rawHTML + "\n",
                attributes: secondaryAttributes()
            )
        case let image as Markdown.Image:
            return blockString(
                imageDisplayText(source: image.source, altText: image.plainText) + "\n",
                attributes: secondaryAttributes()
            )
        default:
            let result = NSMutableAttributedString()
            for child in markup.children {
                result.append(renderBlock(child))
            }
            return result
        }
    }

    private mutating func renderHeading(_ heading: Heading) -> NSMutableAttributedString {
        let result = renderInlineChildren(of: heading)
        appendNewlineIfNeeded(to: result)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.paragraphSpacingBefore = heading.level == 1 ? 7.0 : 5.0
        paragraphStyle.paragraphSpacing = 4.0

        apply(
            [
                .font: style.headingFont(level: heading.level, compatibleWith: traitCollection),
                .foregroundColor: currentTextColor,
                .paragraphStyle: paragraphStyle
            ],
            to: result
        )
        return result
    }

    mutating func renderParagraph(_ paragraph: Paragraph) -> NSMutableAttributedString {
        let result = renderInlineChildren(of: paragraph)
        appendNewlineIfNeeded(to: result)
        applyParagraphStyle(to: result, spacing: 4.0)
        return result
    }

    private mutating func renderCodeBlock(_ codeBlock: CodeBlock) -> NSMutableAttributedString {
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = language?.isEmpty == false ? "\(language!)\n" : ""
        let text = header + code + "\n"

        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: style.codeFont(compatibleWith: traitCollection),
                .foregroundColor: style.codeTextColor,
                .backgroundColor: style.codeBackgroundColor
            ]
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.0
        paragraphStyle.paragraphSpacingBefore = 4.0
        paragraphStyle.paragraphSpacing = 6.0
        apply([.paragraphStyle: paragraphStyle], to: result)
        return result
    }

    private mutating func renderBlockQuote(_ quote: BlockQuote) -> NSMutableAttributedString {
        quoteState.push()
        defer { quoteState.pop() }

        let result = renderBlocks(quote.children)

        trimTrailingNewlines(in: result)
        appendNewlineIfNeeded(to: result)
        applyBlockQuoteIndent(to: result)

        return result
    }

    private func applyBlockQuoteIndent(to attributedString: NSMutableAttributedString) {
        offsetParagraphIndent(
            in: attributedString,
            by: BlockQuoteLayout.indent,
            minimumParagraphSpacing: BlockQuoteLayout.paragraphSpacing
        )
    }

    private func renderThematicBreak() -> NSMutableAttributedString {
        let result = NSMutableAttributedString(
            attachment: HorizontalRuleTextAttachment(
                color: style.dividerColor,
                traitCollection: traitCollection
            )
        )
        result.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = HorizontalRuleTextAttachment.totalHeight
        paragraphStyle.maximumLineHeight = HorizontalRuleTextAttachment.totalHeight
        paragraphStyle.paragraphSpacingBefore = 6.0
        paragraphStyle.paragraphSpacing = 6.0
        apply([.paragraphStyle: paragraphStyle], to: result)
        return result
    }
}

private final class HorizontalRuleTextAttachment: NSTextAttachment {
    static let totalHeight: CGFloat = 14.0

    init(color: UIColor, traitCollection: UITraitCollection) {
        let lineHeight = 1.0 / traitCollection.displayScale
        super.init(data: nil, ofType: nil)
        image = Self.makeImage(
            color: color,
            traitCollection: traitCollection,
            lineHeight: lineHeight
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        CGRect(
            x: 0.0,
            y: -Self.totalHeight / 2.0,
            width: max(1.0, lineFrag.width),
            height: Self.totalHeight
        )
    }

    private static func makeImage(
        color: UIColor,
        traitCollection: UITraitCollection,
        lineHeight: CGFloat
    ) -> UIImage {
        let size = CGSize(width: 1.0, height: totalHeight)
        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        format.opaque = false
        let resolvedColor = color.resolvedColor(with: traitCollection)

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            resolvedColor.setFill()
            rendererContext.fill(
                CGRect(
                    x: 0.0,
                    y: (totalHeight - lineHeight) / 2.0,
                    width: size.width,
                    height: lineHeight
                )
            )
        }.resizableImage(withCapInsets: .zero, resizingMode: .stretch)
    }
}
