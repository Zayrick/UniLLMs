//
//  ChatMarkdownRenderStyle.swift
//  UniLLMs
//
//  Style values for chat Markdown rendering.
//  Created by Codex on 2026/5/12.
//

import UIKit

struct ChatMarkdownRenderStyle {
    var textColor: UIColor
    var secondaryTextColor: UIColor
    var linkColor: UIColor
    var codeTextColor: UIColor
    var codeBackgroundColor: UIColor

    static var assistant: ChatMarkdownRenderStyle {
        ChatMarkdownRenderStyle(
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .systemBlue,
            codeTextColor: .label,
            codeBackgroundColor: .secondarySystemFill
        )
    }

    func bodyFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
    }

    func calloutFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        .preferredFont(forTextStyle: .callout, compatibleWith: traitCollection)
    }

    func codeFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        .monospacedSystemFont(
            ofSize: UIFont.preferredFont(
                forTextStyle: .callout,
                compatibleWith: traitCollection
            ).pointSize,
            weight: .regular
        )
    }

    var dividerColor: UIColor {
        secondaryTextColor.withAlphaComponent(0.35)
    }

    func headingFont(level: Int, compatibleWith traitCollection: UITraitCollection) -> UIFont {
        switch level {
        case 1:
            return .preferredFont(forTextStyle: .title2, compatibleWith: traitCollection)
        case 2:
            return .preferredFont(forTextStyle: .title3, compatibleWith: traitCollection)
        case 3:
            return .preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        default:
            return .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        }
    }
}
