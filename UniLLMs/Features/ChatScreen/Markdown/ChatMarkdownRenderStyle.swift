//
//  ChatMarkdownRenderStyle.swift
//  UniLLMs
//
//  Style values for chat Markdown rendering.
//  Created by Zayrick on 2026/5/12.
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
        let typography: (size: CGFloat, weight: UIFont.Weight, textStyle: UIFont.TextStyle)
        switch level {
        case 1:
            typography = (28.0, .bold, .title1)
        case 2:
            typography = (24.0, .bold, .title2)
        case 3:
            typography = (20.0, .semibold, .title3)
        case 4:
            typography = (18.0, .semibold, .headline)
        case 5:
            typography = (16.0, .medium, .subheadline)
        default:
            typography = (14.0, .medium, .footnote)
        }

        let font = UIFont.systemFont(ofSize: typography.size, weight: typography.weight)
        return UIFontMetrics(forTextStyle: typography.textStyle).scaledFont(
            for: font,
            compatibleWith: traitCollection
        )
    }
}
