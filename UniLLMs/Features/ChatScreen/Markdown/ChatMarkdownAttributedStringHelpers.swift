//
//  ChatMarkdownAttributedStringHelpers.swift
//  UniLLMs
//
//  Attributed string helpers for chat Markdown rendering.
//  Created by Codex on 2026/5/12.
//

import UIKit

extension ChatMarkdownRenderer {
    func blockString(
        _ string: String,
        attributes: [NSAttributedString.Key: Any],
        paragraphSpacing: CGFloat = 4.0
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: string, attributes: attributes)
        applyParagraphStyle(to: result, spacing: paragraphSpacing)
        return result
    }

    func applyParagraphStyle(to attributedString: NSMutableAttributedString, spacing: CGFloat) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.paragraphSpacing = spacing
        apply([.paragraphStyle: paragraphStyle], to: attributedString)
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
            .font: style.bodyFont(compatibleWith: traitCollection),
            .foregroundColor: style.textColor
        ]
    }

    func secondaryAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: style.calloutFont(compatibleWith: traitCollection),
            .foregroundColor: style.secondaryTextColor
        ]
    }
}
