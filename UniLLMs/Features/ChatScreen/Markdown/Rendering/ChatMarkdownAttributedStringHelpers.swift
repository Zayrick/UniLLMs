//
//  ChatMarkdownAttributedStringHelpers.swift
//  UniLLMs
//
//  Attributed string helpers for chat Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import UIKit

extension NSAttributedString.Key {
    nonisolated static let chatAccessibilityText = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.accessibilityText"
    )

    nonisolated static let chatFontSymbolicTraits = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.fontSymbolicTraits"
    )
}

fileprivate struct ChatMarkdownAccessibilityTextAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
    typealias Value = String

    static let name = "UniLLMs.ChatMarkdown.accessibilityText"
}

fileprivate struct ChatMarkdownAttributeScope: AttributeScope {
    let accessibilityText: ChatMarkdownAccessibilityTextAttribute
}

extension AttributeScopes {
    fileprivate var chatMarkdown: ChatMarkdownAttributeScope.Type {
        ChatMarkdownAttributeScope.self
    }
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

        guard let attributedString = try? AttributedString(
            self,
            including: \.chatMarkdown
        ) else {
            return string.replacingOccurrences(of: "\u{fffc}", with: "")
        }

        var result = ""
        for run in attributedString.runs {
            if let accessibilityText = run[ChatMarkdownAccessibilityTextAttribute.self] {
                result += accessibilityText
            } else {
                result += String(attributedString.characters[run.range])
                    .replacingOccurrences(of: "\u{fffc}", with: "")
            }
        }
        return result
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

        var location = 0
        while location < attributedString.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let existingStyle = attributedString.attribute(
                .paragraphStyle,
                at: location,
                effectiveRange: &effectiveRange
            ) as? NSParagraphStyle
            let paragraphStyle: NSMutableParagraphStyle
            if let existingStyle,
               let mutableStyle = existingStyle.mutableCopy() as? NSMutableParagraphStyle {
                paragraphStyle = mutableStyle
            } else {
                paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = style.bodyLineSpacing(compatibleWith: traitCollection)
                paragraphStyle.paragraphSpacing = style.bodyParagraphSpacing(compatibleWith: traitCollection)
            }

            transform(paragraphStyle)
            attributedString.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: effectiveRange
            )
            location = effectiveRange.location + max(effectiveRange.length, 1)
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

        var location = 0
        while location < attributedString.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let positions = attributedString.attribute(
                .chatBlockQuoteBarPositions,
                at: location,
                effectiveRange: &effectiveRange
            ) as? [CGFloat]

            if let positions, !positions.isEmpty {
                attributedString.addAttribute(
                    .chatBlockQuoteBarPositions,
                    value: ChatMarkdownBlockQuoteStyle.shiftingBarPositions(
                        positions,
                        by: offset
                    ),
                    range: effectiveRange
                )
            }
            location = effectiveRange.location + max(effectiveRange.length, 1)
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
        let font = currentBodyFont()
        return [
            .font: font,
            .chatFontSymbolicTraits: font.fontDescriptor.symbolicTraits.rawValue,
            .foregroundColor: currentTextColor
        ]
    }

    func secondaryAttributes() -> [NSAttributedString.Key: Any] {
        let font = style.calloutFont(compatibleWith: traitCollection)
        return [
            .font: font,
            .chatFontSymbolicTraits: font.fontDescriptor.symbolicTraits.rawValue,
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
