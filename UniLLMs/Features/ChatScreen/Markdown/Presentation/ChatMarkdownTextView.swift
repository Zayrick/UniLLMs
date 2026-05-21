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
    private let markdownLayoutManager: ChatMarkdownLayoutManager
    private let markdownTextContainer: NSTextContainer

    private var currentAttributedText = NSAttributedString()

    init(attributedText: NSAttributedString) {
        let textStorage = NSTextStorage()
        let layoutManager = ChatMarkdownLayoutManager()
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
        currentAttributedText = attributedText
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    /// Reconcile text storage without assigning `attributedText` wholesale.
    /// UIKit treats a whole attributedText assignment as new content; keeping
    /// TextKit storage alive avoids link-color churn and preserves layout state.
    func replaceTailAttributedText(_ newText: NSAttributedString) {
        guard !currentAttributedText.isEqual(to: newText) else {
            return
        }

        let oldString = markdownTextStorage.string as NSString
        let newString = newText.string as NSString
        let oldLength = oldString.length
        let newLength = newString.length

        var prefix = 0
        let maxPrefix = min(oldLength, newLength)
        while prefix < maxPrefix,
              oldString.character(at: prefix) == newString.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        let maxSuffix = min(oldLength - prefix, newLength - prefix)
        while suffix < maxSuffix,
              oldString.character(at: oldLength - 1 - suffix)
              == newString.character(at: newLength - 1 - suffix) {
            suffix += 1
        }

        let replacedRange = NSRange(location: prefix, length: oldLength - prefix - suffix)
        let insertedRange = NSRange(location: prefix, length: newLength - prefix - suffix)

        markdownTextStorage.beginEditing()
        if replacedRange.length > 0 || insertedRange.length > 0 {
            markdownTextStorage.replaceCharacters(
                in: replacedRange,
                with: newText.attributedSubstring(from: insertedRange)
            )
        }
        synchronizeAttributesNoEditing(with: newText)
        markdownTextStorage.endEditing()

        accessibilityLabel = newString as String
        currentAttributedText = newText
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    /// Legacy entry-point kept for callers that have not migrated yet.
    func updateMarkdownAttributedTextWithBlur(_ newText: NSAttributedString) {
        replaceTailAttributedText(newText)
    }

    private func synchronizeAttributesNoEditing(with newText: NSAttributedString) {
        guard markdownTextStorage.length == newText.length, newText.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: newText.length)
        newText.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let currentAttributes = markdownTextStorage.attributes(
                at: range.location,
                effectiveRange: nil
            )
            if !NSDictionary(dictionary: currentAttributes).isEqual(NSDictionary(dictionary: attributes)) {
                markdownTextStorage.setAttributes(attributes, range: range)
            }
        }
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        isScrollEnabled = false
        dataDetectorTypes = []
        linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        tintColor = .systemBlue
        textContainerInset = .zero
        markdownTextContainer.lineFragmentPadding = 0.0
        markdownLayoutManager.usesFontLeading = true
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
        translatesAutoresizingMaskIntoConstraints = false
    }
}

private final class ChatMarkdownLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawBlockQuoteBars(forGlyphRange: glyphsToShow, at: origin)
        drawInlineCodeBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawBlockQuoteBars(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let textStorage else {
            return
        }

        ChatMarkdownBlockQuoteStyle.barColor.setFill()

        enumerateLineFragments(forGlyphRange: glyphsToShow) { lineFragmentRect, _, _, lineGlyphRange, _ in
            let visibleGlyphRange = NSIntersectionRange(lineGlyphRange, glyphsToShow)
            guard visibleGlyphRange.length > 0 else {
                return
            }

            let lineCharacterRange = self.characterRange(
                forGlyphRange: visibleGlyphRange,
                actualGlyphRange: nil
            )
            guard lineCharacterRange.length > 0 else {
                return
            }

            let barPositions = self.blockQuoteBarPositions(
                in: lineCharacterRange,
                textStorage: textStorage
            )
            guard !barPositions.isEmpty else {
                return
            }

            let lineRect = lineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
            for barPosition in barPositions {
                let barRect = CGRect(
                    x: lineRect.minX + barPosition,
                    y: lineRect.minY,
                    width: ChatMarkdownBlockQuoteStyle.barWidth,
                    height: lineRect.height
                )
                UIRectFill(barRect)
            }
        }
    }

    private func blockQuoteBarPositions(
        in characterRange: NSRange,
        textStorage: NSTextStorage
    ) -> [CGFloat] {
        var result: [CGFloat] = []
        textStorage.enumerateAttribute(
            .chatBlockQuoteBarPositions,
            in: characterRange
        ) { value, _, _ in
            guard let positions = value as? [CGFloat] else {
                return
            }

            for position in positions where !result.contains(position) {
                result.append(position)
            }
        }

        return result.sorted()
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
