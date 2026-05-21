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

    private var displayLink: CADisplayLink?
    private var animatingRanges: [NSRange: CFTimeInterval] = [:]
    private var targetAttributedText: NSAttributedString?

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
        targetAttributedText = attributedText
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    /// Replace the trailing portion of the rendered text without touching the
    /// common prefix or common suffix. This keeps glyph layout for unchanged
    /// regions in place — which is the whole point of the new streaming
    /// pipeline — and produces an `NSRange` describing the *inserted* slice
    /// so the blur animation can target only the freshly-arrived characters.
    func replaceTailAttributedText(_ newText: NSAttributedString) {
        let oldString = markdownTextStorage.string as NSString
        let newString = newText.string as NSString
        let oldLength = oldString.length
        let newLength = newString.length

        // Common prefix length in UTF-16 units.
        var prefix = 0
        let maxPrefix = min(oldLength, newLength)
        while prefix < maxPrefix,
              oldString.character(at: prefix) == newString.character(at: prefix) {
            prefix += 1
        }

        // Common suffix length — must not overlap the common prefix.
        var suffix = 0
        let maxSuffix = min(oldLength - prefix, newLength - prefix)
        while suffix < maxSuffix,
              oldString.character(at: oldLength - 1 - suffix)
              == newString.character(at: newLength - 1 - suffix) {
            suffix += 1
        }

        let replacedRange = NSRange(location: prefix, length: oldLength - prefix - suffix)
        let insertedRange = NSRange(location: prefix, length: newLength - prefix - suffix)

        if replacedRange.length == 0, insertedRange.length == 0 {
            // Pure attribute change at most — fall back to wholesale swap so
            // any restyling (e.g. emphasis applied to existing chars) lands.
            if !newText.isEqual(to: markdownTextStorage) {
                markdownTextStorage.setAttributedString(newText)
                accessibilityLabel = newText.string
                targetAttributedText = newText
                invalidateIntrinsicContentSize()
                setNeedsDisplay()
            }
            return
        }

        let insertedSlice = newText.attributedSubstring(from: insertedRange)
        let mutableInsert = NSMutableAttributedString(attributedString: insertedSlice)

        // Only animate when the change is a tail extension: replacedRange has
        // length 0 (pure insertion) or the inserted region is longer than the
        // replaced one (predictive closer growth still counts). Mid-string
        // edits without a net growth skip the blur to avoid distracting flashes.
        let shouldAnimate = insertedRange.length > 0 && replacedRange.length == 0
        if shouldAnimate {
            applyBlur(to: mutableInsert, in: NSRange(location: 0, length: mutableInsert.length), progress: 0.0)
        }

        markdownTextStorage.beginEditing()
        markdownTextStorage.replaceCharacters(in: replacedRange, with: mutableInsert)
        markdownTextStorage.endEditing()

        accessibilityLabel = newString as String
        targetAttributedText = newText
        invalidateIntrinsicContentSize()
        setNeedsDisplay()

        if shouldAnimate {
            animatingRanges[insertedRange] = CACurrentMediaTime()
            startDisplayLink()
        }
    }

    /// Legacy entry-point kept for callers that have not migrated yet.
    func updateMarkdownAttributedTextWithBlur(_ newText: NSAttributedString) {
        replaceTailAttributedText(newText)
    }
    
    private func applyBlur(to mutableText: NSMutableAttributedString, in range: NSRange, progress: CGFloat) {
        let alpha = min(1.0, max(0.0, progress))
        let blurRadius = 6.0 * (1.0 - alpha)
        
        mutableText.enumerateAttribute(.foregroundColor, in: range, options: []) { colorValue, colorRange, _ in
            guard let color = colorValue as? UIColor else { return }
            
            let newColor = color.withAlphaComponent(color.cgColor.alpha * alpha)
            mutableText.addAttribute(.foregroundColor, value: newColor, range: colorRange)
            
            if progress < 1.0 {
                let shadow = NSShadow()
                shadow.shadowBlurRadius = blurRadius
                shadow.shadowColor = color.withAlphaComponent(color.cgColor.alpha * (1.0 - alpha))
                shadow.shadowOffset = .zero
                mutableText.addAttribute(.shadow, value: shadow, range: colorRange)
            } else {
                mutableText.removeAttribute(.shadow, range: colorRange)
            }
        }
    }
    
    private func startDisplayLink() {
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        guard let target = targetAttributedText else {
            stopDisplayLink()
            return
        }

        let currentTime = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.4

        var hasActiveAnimations = false
        var completedRanges: [NSRange] = []

        markdownTextStorage.beginEditing()
        for (range, startTime) in animatingRanges {
            guard range.upperBound <= markdownTextStorage.length,
                  range.upperBound <= target.length else {
                completedRanges.append(range)
                continue
            }

            let elapsed = currentTime - startTime
            let progress = CGFloat(min(1.0, max(0.0, elapsed / duration)))
            applyBlurToStorage(in: range, progress: progress, target: target)

            if progress >= 1.0 {
                completedRanges.append(range)
            } else {
                hasActiveAnimations = true
            }
        }
        markdownTextStorage.endEditing()

        for r in completedRanges {
            animatingRanges.removeValue(forKey: r)
        }

        if !hasActiveAnimations {
            stopDisplayLink()
        }
    }

    private func applyBlurToStorage(in range: NSRange, progress: CGFloat, target: NSAttributedString) {
        let alpha = min(1.0, max(0.0, progress))
        let blurRadius = 6.0 * (1.0 - alpha)

        target.enumerateAttribute(.foregroundColor, in: range, options: []) { colorValue, colorRange, _ in
            guard let color = colorValue as? UIColor else { return }
            let baseAlpha = color.cgColor.alpha
            let blendedColor = color.withAlphaComponent(baseAlpha * alpha)
            markdownTextStorage.addAttribute(.foregroundColor, value: blendedColor, range: colorRange)

            if progress < 1.0 {
                let shadow = NSShadow()
                shadow.shadowBlurRadius = blurRadius
                shadow.shadowColor = color.withAlphaComponent(baseAlpha * (1.0 - alpha))
                shadow.shadowOffset = .zero
                markdownTextStorage.addAttribute(.shadow, value: shadow, range: colorRange)
            } else {
                markdownTextStorage.removeAttribute(.shadow, range: colorRange)
            }
        }
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
