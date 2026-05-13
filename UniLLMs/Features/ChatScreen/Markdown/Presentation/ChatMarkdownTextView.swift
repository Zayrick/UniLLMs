//
//  ChatMarkdownTextView.swift
//  UniLLMs
//
//  TextKit-backed Markdown text rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

final class ChatMarkdownTextView: UITextView {
    private let markdownTextStorage: NSTextStorage
    private let markdownLayoutManager: ChatMarkdownInlineCodeLayoutManager
    private let markdownTextContainer: NSTextContainer

    init(attributedText: NSAttributedString) {
        let textStorage = NSTextStorage()
        let layoutManager = ChatMarkdownInlineCodeLayoutManager()
        let textContainer = NSTextContainer(size: .zero)

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        markdownTextStorage = textStorage
        markdownLayoutManager = layoutManager
        markdownTextContainer = textContainer

        super.init(frame: .zero, textContainer: textContainer)
        configure()
        setMarkdownAttributedText(attributedText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMarkdownLineBreakMode(_ lineBreakMode: NSLineBreakMode) {
        markdownTextContainer.lineBreakMode = lineBreakMode
        markdownLayoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: markdownTextStorage.length),
            actualCharacterRange: nil
        )
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    private func setMarkdownAttributedText(_ attributedText: NSAttributedString) {
        markdownTextStorage.setAttributedString(attributedText)
        accessibilityLabel = attributedText.string
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        isScrollEnabled = false
        dataDetectorTypes = [.link]
        textContainerInset = .zero
        markdownTextContainer.lineFragmentPadding = 0.0
        markdownLayoutManager.usesFontLeading = true
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
        translatesAutoresizingMaskIntoConstraints = false
    }
}

private final class ChatMarkdownInlineCodeLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawInlineCodeBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawInlineCodeBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let textStorage else {
            return
        }

        let characterRange = self.characterRange(
            forGlyphRange: glyphsToShow,
            actualGlyphRange: nil
        )

        textStorage.enumerateAttribute(
            .chatInlineCodeBackgroundColor,
            in: characterRange
        ) { value, characterAttributeRange, _ in
            guard let color = value as? UIColor else {
                return
            }

            let glyphAttributeRange = self.glyphRange(
                forCharacterRange: characterAttributeRange,
                actualCharacterRange: nil
            )
            let visibleGlyphRange = NSIntersectionRange(glyphAttributeRange, glyphsToShow)
            guard visibleGlyphRange.length > 0 else {
                return
            }

            let cornerRadius = textStorage.attribute(
                .chatInlineCodeCornerRadius,
                at: characterAttributeRange.location,
                effectiveRange: nil
            ) as? CGFloat ?? ChatMarkdownInlineCodeStyle.cornerRadius

            self.drawInlineCodeBackground(
                color: color,
                cornerRadius: cornerRadius,
                glyphRange: visibleGlyphRange,
                containerOrigin: origin
            )
        }
    }

    private func drawInlineCodeBackground(
        color: UIColor,
        cornerRadius: CGFloat,
        glyphRange: NSRange,
        containerOrigin: CGPoint
    ) {
        enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, usedRect, textContainer, lineGlyphRange, _ in
            let lineRange = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard lineRange.length > 0 else {
                return
            }

            let glyphRect = self.boundingRect(forGlyphRange: lineRange, in: textContainer)
            guard glyphRect.width > 0.0, lineFragmentRect.height > 0.0 else {
                return
            }

            let lineHeight = self.inlineCodeBackgroundHeight(
                forGlyphRange: lineRange,
                lineFragmentHeight: lineFragmentRect.height,
                usedRectHeight: usedRect.height
            )
            let lineCenterY = usedRect.height > 0.0 ? usedRect.midY : glyphRect.midY
            let rect = CGRect(
                x: glyphRect.minX - ChatMarkdownInlineCodeStyle.horizontalPadding + containerOrigin.x,
                y: lineCenterY - lineHeight / 2.0 + containerOrigin.y,
                width: glyphRect.width + ChatMarkdownInlineCodeStyle.horizontalPadding * 2.0,
                height: lineHeight
            )

            color.setFill()
            UIBezierPath(
                roundedRect: rect,
                cornerRadius: min(cornerRadius, rect.height / 2.0)
            ).fill()
        }
    }

    private func inlineCodeBackgroundHeight(
        forGlyphRange glyphRange: NSRange,
        lineFragmentHeight: CGFloat,
        usedRectHeight: CGFloat
    ) -> CGFloat {
        let contentHeight = max(
            inlineCodeFontLineHeight(forGlyphRange: glyphRange),
            usedRectHeight
        )
        let availableHeight = max(
            1.0,
            lineFragmentHeight - ChatMarkdownInlineCodeStyle.interLineGap
        )
        return min(contentHeight, availableHeight)
    }

    private func inlineCodeFontLineHeight(forGlyphRange glyphRange: NSRange) -> CGFloat {
        guard let textStorage else {
            return 0.0
        }

        let characterRange = self.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        guard characterRange.location < textStorage.length,
              let font = textStorage.attribute(
                .font,
                at: characterRange.location,
                effectiveRange: nil
              ) as? UIFont else {
            return 0.0
        }

        return font.lineHeight
    }
}
