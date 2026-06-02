//
//  ChatMarkdownLeafBlockRenderer.swift
//  UniLLMs
//
//  Leaf block Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import Markdown
import UIKit

final class ChatMarkdownLeafBlockRenderer {
    private let context: ChatMarkdownRenderingContext
    private let inlineRenderer: ChatMarkdownInlineRenderer
    private let htmlBlockRenderer: ChatMarkdownHTMLBlockRenderer

    init(
        context: ChatMarkdownRenderingContext,
        inlineRenderer: ChatMarkdownInlineRenderer
    ) {
        self.context = context
        self.inlineRenderer = inlineRenderer
        htmlBlockRenderer = ChatMarkdownHTMLBlockRenderer(context: context)
    }

    func renderHeading(_ heading: Heading) -> NSMutableAttributedString {
        let result = inlineRenderer.renderChildren(
            of: heading,
            font: context.style.headingFont(level: heading.level, compatibleWith: context.traitCollection),
            foregroundColor: context.currentTextColor
        )
        context.appendNewlineIfNeeded(to: result)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = context.style.headingLineSpacing(
            level: heading.level,
            compatibleWith: context.traitCollection
        )
        paragraphStyle.paragraphSpacingBefore = context.style.headingParagraphSpacingBefore(
            level: heading.level,
            compatibleWith: context.traitCollection
        )
        paragraphStyle.paragraphSpacing = context.style.headingParagraphSpacingAfter(
            level: heading.level,
            compatibleWith: context.traitCollection
        )

        context.apply([.paragraphStyle: paragraphStyle], to: result)
        return result
    }

    func renderParagraph(_ paragraph: Paragraph) -> NSMutableAttributedString {
        let result = inlineRenderer.renderChildren(of: paragraph)
        context.appendNewlineIfNeeded(to: result)
        context.applyParagraphStyle(to: result)
        return result
    }

    func renderCodeBlock(_ codeBlock: CodeBlock) -> NSMutableAttributedString {
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = language.flatMap { $0.isEmpty ? nil : "\($0)\n" } ?? ""
        let text = header + code + "\n"

        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: context.style.codeFont(compatibleWith: context.traitCollection),
                .foregroundColor: context.style.codeTextColor,
                .backgroundColor: context.style.codeBlockBackgroundColor
            ]
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = context.style.codeLineSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacingBefore = context.style.bodyParagraphSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacing = context.style.bodyParagraphSpacing(compatibleWith: context.traitCollection)
        context.apply([.paragraphStyle: paragraphStyle], to: result)
        return result
    }

    func renderThematicBreak() -> NSMutableAttributedString {
        let result = NSMutableAttributedString(
            attachment: HorizontalRuleTextAttachment(
                color: context.style.dividerColor,
                traitCollection: context.traitCollection
            )
        )
        result.append(NSAttributedString(string: "\n", attributes: context.bodyAttributes()))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = HorizontalRuleTextAttachment.totalHeight
        paragraphStyle.maximumLineHeight = HorizontalRuleTextAttachment.totalHeight
        paragraphStyle.paragraphSpacingBefore = context.style.bodyParagraphSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacing = context.style.bodyParagraphSpacing(compatibleWith: context.traitCollection)
        context.apply([.paragraphStyle: paragraphStyle], to: result)
        return result
    }

    func renderHTMLBlock(_ htmlBlock: HTMLBlock) -> NSMutableAttributedString {
        htmlBlockRenderer.renderHTMLBlock(htmlBlock.rawHTML)
    }

    func renderImage(_ image: Markdown.Image) -> NSMutableAttributedString {
        context.blockString(
            context.imageDisplayText(source: image.source, altText: image.plainText) + "\n",
            attributes: context.secondaryAttributes()
        )
    }
}

nonisolated final class HorizontalRuleTextAttachment: NSTextAttachment {
    nonisolated static let totalHeight: CGFloat = 14.0

    nonisolated init(color: UIColor, traitCollection: UITraitCollection) {
        let lineHeight = 1.0 / traitCollection.displayScale
        super.init(data: nil, ofType: nil)
        image = Self.makeImage(
            color: color,
            traitCollection: traitCollection,
            lineHeight: lineHeight
        )
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    nonisolated override func attachmentBounds(
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

    private nonisolated static func makeImage(
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
