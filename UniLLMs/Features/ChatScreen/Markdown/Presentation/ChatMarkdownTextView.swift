//
//  ChatMarkdownTextView.swift
//  UniLLMs
//
//  TextKit-backed Markdown text rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

final class ChatMarkdownTextView: UITextView {
    private enum Fade {
        static let duration: TimeInterval = 0.18
        static let cleanupDelay: TimeInterval = 0.05
        static let minimumLayerSize: CGFloat = 0.5
    }

    private let markdownTextStorage: NSTextStorage
    private let markdownLayoutManager: ChatMarkdownLayoutManager
    private let markdownTextContainer: NSTextContainer

    private var currentAttributedText = NSAttributedString()
    private var textFadeMaskGeneration = 0

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
        removeTextFadeMask()
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    private func setMarkdownAttributedText(_ attributedText: NSAttributedString) {
        removeTextFadeMask()
        markdownTextStorage.setAttributedString(attributedText)
        accessibilityLabel = attributedText.chatAccessibilityString
        currentAttributedText = attributedText
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    /// Reconcile text storage without assigning `attributedText` wholesale.
    /// UIKit treats a whole attributedText assignment as new content; keeping
    /// TextKit storage alive avoids link-color churn and preserves layout state.
    func replaceMarkdownAttributedText(
        _ newText: NSAttributedString,
        animated: Bool = false
    ) {
        guard !currentAttributedText.isEqual(to: newText) else {
            return
        }

        let canAppendOnly = canAppendOnly(newText)
        let appendedRange = NSRange(
            location: currentAttributedText.length,
            length: max(0, newText.length - currentAttributedText.length)
        )

        if canAppendOnly {
            let tailRange = NSRange(
                location: currentAttributedText.length,
                length: newText.length - currentAttributedText.length
            )
            markdownTextStorage.append(newText.attributedSubstring(from: tailRange))
        } else {
            removeTextFadeMask()
            markdownTextStorage.setAttributedString(newText)
        }

        accessibilityLabel = newText.chatAccessibilityString
        currentAttributedText = newText
        invalidateIntrinsicContentSize()
        setNeedsDisplay()

        if animated, canAppendOnly {
            animateAppendedText(in: appendedRange)
        }
    }

    private func canAppendOnly(_ newText: NSAttributedString) -> Bool {
        let oldLength = currentAttributedText.length
        guard newText.length > oldLength else {
            return false
        }
        let newPrefix = newText.attributedSubstring(
            from: NSRange(location: 0, length: oldLength)
        )
        return currentAttributedText.isEqual(to: newPrefix)
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        isScrollEnabled = false
        textContainerInset = .zero
        markdownTextContainer.lineFragmentPadding = 0.0
        markdownLayoutManager.usesFontLeading = true
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func animateAppendedText(in characterRange: NSRange) {
        guard characterRange.length > 0,
              !UIAccessibility.isReduceMotionEnabled,
              bounds.width > 0.0,
              bounds.height > 0.0 else {
            removeTextFadeMask()
            return
        }

        layoutIfNeeded()
        markdownLayoutManager.ensureLayout(for: markdownTextContainer)

        let glyphRange = markdownLayoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else {
            removeTextFadeMask()
            return
        }

        var lineFragments: [ChatMarkdownTextFadeMaskPlan.LineFragment] = []
        let origin = textContainerOrigin

        markdownLayoutManager.enumerateLineFragments(
            forGlyphRange: glyphRange
        ) { lineFragmentRect, usedRect, textContainer, lineGlyphRange, _ in
            let lineChangedGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard lineChangedGlyphRange.length > 0 else {
                return
            }

            let changedRect = self.markdownLayoutManager.boundingRect(
                forGlyphRange: lineChangedGlyphRange,
                in: textContainer
            ).offsetBy(dx: origin.x, dy: origin.y)
            let lineFrame = lineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
            let usedFrame = usedRect.offsetBy(dx: origin.x, dy: origin.y)
            lineFragments.append(
                ChatMarkdownTextFadeMaskPlan.LineFragment(
                    changedRect: changedRect,
                    lineFrame: lineFrame,
                    usedFrame: usedFrame
                )
            )
        }

        let fadeMaskPlan = ChatMarkdownTextFadeMaskPlan(
            bounds: bounds,
            minimumLayerSize: Fade.minimumLayerSize,
            fragments: lineFragments
        )
        guard !fadeMaskPlan.isEmpty else {
            removeTextFadeMask()
            return
        }

        textFadeMaskGeneration += 1
        let generation = textFadeMaskGeneration
        let maskLayer = CALayer()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        for opaqueFrame in fadeMaskPlan.opaqueFrames {
            addOpaqueMaskLayer(to: maskLayer, frame: opaqueFrame)
        }

        for fadeFrame in fadeMaskPlan.fadeFrames {
            let fadeLayer = CALayer()
            fadeLayer.backgroundColor = UIColor.black.cgColor
            fadeLayer.frame = fadeFrame
            fadeLayer.opacity = 1.0
            maskLayer.addSublayer(fadeLayer)

            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.0
            animation.toValue = 1.0
            animation.duration = Fade.duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation.fillMode = .both
            animation.isRemovedOnCompletion = true
            fadeLayer.add(animation, forKey: "chatMarkdownFadeIn")
        }

        layer.mask = maskLayer
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + Fade.duration + Fade.cleanupDelay) { [weak self] in
            guard let self, self.textFadeMaskGeneration == generation else {
                return
            }
            self.layer.mask = nil
        }
    }

    private func addOpaqueMaskLayer(to maskLayer: CALayer, frame: CGRect) {
        let layer = CALayer()
        layer.backgroundColor = UIColor.black.cgColor
        layer.frame = frame
        maskLayer.addSublayer(layer)
    }

    private func removeTextFadeMask() {
        textFadeMaskGeneration += 1
        layer.mask = nil
    }

    private var textContainerOrigin: CGPoint {
        CGPoint(
            x: textContainerInset.left - contentOffset.x,
            y: textContainerInset.top - contentOffset.y
        )
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
