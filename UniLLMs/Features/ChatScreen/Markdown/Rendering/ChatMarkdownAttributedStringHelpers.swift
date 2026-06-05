//
//  ChatMarkdownAttributedStringHelpers.swift
//  UniLLMs
//
//  Attributed string helpers for chat Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import UIKit

extension NSAttributedString.Key {
    static let chatAccessibilityText = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.accessibilityText"
    )
    static let chatFootnoteContent = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.footnoteContent"
    )
}

enum ChatMarkdownCheckboxRenderer {
    static func attributedString(
        isChecked: Bool,
        font: UIFont,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let accessibilityText = isChecked ? String(localized: .markdownTaskChecked) : String(localized: .markdownTaskUnchecked)
        var resolvedAttributes = attributes
        resolvedAttributes[.chatAccessibilityText] = accessibilityText

        let name = isChecked ? "checkmark.square" : "square"
        let configuration = UIImage.SymbolConfiguration(font: font, scale: .medium)
        guard let image = UIImage(systemName: name, withConfiguration: configuration) else {
            let fallback = isChecked ? "☑" : "☐"
            return NSAttributedString(string: fallback, attributes: resolvedAttributes)
        }

        let attachment = NSTextAttachment()
        attachment.image = image.withRenderingMode(.alwaysTemplate)

        let symbol = NSMutableAttributedString(attachment: attachment)
        symbol.addAttributes(
            resolvedAttributes,
            range: NSRange(location: 0, length: symbol.length)
        )
        return symbol
    }
}

extension NSAttributedString {
    var chatAccessibilityString: String {
        guard length > 0 else {
            return ""
        }

        let backingString = string as NSString
        var result = ""
        enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, range, _ in
            if let accessibilityText = attributes[.chatAccessibilityText] as? String {
                result += accessibilityText
                return
            }

            let substring = backingString.substring(with: range)
            result += substring.replacingOccurrences(of: "\u{fffc}", with: "")
        }
        return result
    }
}

extension NSMutableAttributedString {
    func appendWithChatInlineCodeVisualSpacing(_ attributedString: NSAttributedString) {
        applyChatInlineCodeVisualSpacing(beforeAppending: attributedString)
        append(attributedString)
    }

    private func applyChatInlineCodeVisualSpacing(beforeAppending attributedString: NSAttributedString) {
        guard length > 0, attributedString.length > 0 else {
            return
        }

        let currentString = string as NSString
        let incomingString = attributedString.string as NSString
        let previousRange = currentString.rangeOfComposedCharacterSequence(at: length - 1)
        let nextRange = incomingString.rangeOfComposedCharacterSequence(at: 0)

        guard !Self.isWhitespaceOnly(currentString.substring(with: previousRange)),
              !Self.isWhitespaceOnly(incomingString.substring(with: nextRange)) else {
            return
        }

        let previousIsInlineCode = attribute(
            .chatInlineCodeBackgroundColor,
            at: previousRange.location,
            effectiveRange: nil
        ) != nil
        let nextIsInlineCode = attributedString.attribute(
            .chatInlineCodeBackgroundColor,
            at: nextRange.location,
            effectiveRange: nil
        ) != nil

        guard previousIsInlineCode != nextIsInlineCode,
              attribute(
                  .chatInlineCodeBoundarySpacing,
                  at: previousRange.location,
                  effectiveRange: nil
              ) == nil else {
            return
        }

        let spacing = ChatMarkdownInlineCodeStyle.boundarySpacing
        let kern = Self.numericAttributeValue(
            attribute(.kern, at: previousRange.location, effectiveRange: nil)
        ) + spacing

        addAttribute(.kern, value: kern, range: previousRange)
        addAttribute(.chatInlineCodeBoundarySpacing, value: spacing, range: previousRange)
    }

    private static func isWhitespaceOnly(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func numericAttributeValue(_ value: Any?) -> CGFloat {
        if let value = value as? CGFloat {
            return value
        }
        if let value = value as? NSNumber {
            return CGFloat(truncating: value)
        }
        return 0.0
    }
}

extension ChatMarkdownRenderingContext {
    func blockString(
        _ string: String,
        attributes: [NSAttributedString.Key: Any],
        paragraphSpacing: CGFloat? = nil
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: string, attributes: attributes)
        applyParagraphStyle(to: result, spacing: paragraphSpacing)
        return result
    }

    func applyParagraphStyle(
        to attributedString: NSMutableAttributedString,
        spacing: CGFloat? = nil
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = style.bodyLineSpacing(compatibleWith: traitCollection)
        paragraphStyle.paragraphSpacing = spacing ?? style.bodyParagraphSpacing(compatibleWith: traitCollection)
        apply([.paragraphStyle: paragraphStyle], to: attributedString)
    }

    func transformParagraphStyles(
        in attributedString: NSMutableAttributedString,
        transform: (NSMutableParagraphStyle) -> Void
    ) {
        guard attributedString.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        var paragraphRanges: [(style: NSParagraphStyle?, range: NSRange)] = []
        attributedString.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            paragraphRanges.append((value as? NSParagraphStyle, range))
        }

        for paragraphRange in paragraphRanges {
            let paragraphStyle: NSMutableParagraphStyle
            if let existingStyle = paragraphRange.style,
               let mutableStyle = existingStyle.mutableCopy() as? NSMutableParagraphStyle {
                paragraphStyle = mutableStyle
            } else {
                paragraphStyle = NSMutableParagraphStyle()
            }

            transform(paragraphStyle)
            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraphRange.range)
        }
    }

    func offsetParagraphIndent(
        in attributedString: NSMutableAttributedString,
        by offset: CGFloat,
        minimumParagraphSpacing: CGFloat? = nil
    ) {
        transformParagraphStyles(in: attributedString) { paragraphStyle in
            paragraphStyle.firstLineHeadIndent += offset
            paragraphStyle.headIndent += offset
            if let minimumParagraphSpacing {
                paragraphStyle.paragraphSpacing = max(
                    paragraphStyle.paragraphSpacing,
                    minimumParagraphSpacing
                )
            }
            paragraphStyle.tabStops = paragraphStyle.tabStops.map { tab in
                NSTextTab(
                    textAlignment: tab.alignment,
                    location: tab.location + offset,
                    options: tab.options
                )
            }
        }
        shiftBlockQuoteBars(in: attributedString, by: offset)
    }

    private func shiftBlockQuoteBars(
        in attributedString: NSMutableAttributedString,
        by offset: CGFloat
    ) {
        guard attributedString.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        var updates: [(positions: [CGFloat], range: NSRange)] = []
        attributedString.enumerateAttribute(.chatBlockQuoteBarPositions, in: fullRange) { value, range, _ in
            guard let positions = value as? [CGFloat], !positions.isEmpty else {
                return
            }

            updates.append((positions.map { $0 + offset }, range))
        }

        for update in updates {
            attributedString.addAttribute(
                .chatBlockQuoteBarPositions,
                value: update.positions,
                range: update.range
            )
        }
    }

    func appendNewlineIfNeeded(to attributedString: NSMutableAttributedString) {
        guard attributedString.length == 0 || !attributedString.string.hasSuffix("\n") else {
            return
        }

        attributedString.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
    }

    func trimTrailingNewlines(in attributedString: NSMutableAttributedString) {
        while attributedString.length > 0 && attributedString.string.hasSuffix("\n") {
            attributedString.deleteCharacters(in: NSRange(location: attributedString.length - 1, length: 1))
        }
    }

    func apply(_ attributes: [NSAttributedString.Key: Any], to attributedString: NSMutableAttributedString) {
        guard attributedString.length > 0 else {
            return
        }

        attributedString.addAttributes(attributes, range: NSRange(location: 0, length: attributedString.length))
    }

    func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: currentBodyFont(),
            .foregroundColor: currentTextColor
        ]
    }

    func secondaryAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: style.calloutFont(compatibleWith: traitCollection),
            .foregroundColor: style.secondaryTextColor
        ]
    }

    var currentTextColor: UIColor {
        style.textColor
    }

    func currentBodyFont() -> UIFont {
        style.bodyFont(compatibleWith: traitCollection)
    }

    func imageDisplayText(source: String?, altText: String) -> String {
        let label = altText.isEmpty ? String(localized: .markdownImage) : altText
        guard let source,
              !source.isEmpty else {
            return "[\(label)]"
        }

        return "[\(label): \(source)]"
    }
}
