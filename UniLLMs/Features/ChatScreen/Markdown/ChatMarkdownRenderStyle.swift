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

    var bodyFont: UIFont {
        .preferredFont(forTextStyle: .body)
    }

    var calloutFont: UIFont {
        .preferredFont(forTextStyle: .callout)
    }

    var codeFont: UIFont {
        .monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize,
            weight: .regular
        )
    }

    var dividerColor: UIColor {
        secondaryTextColor.withAlphaComponent(0.35)
    }

    func headingFont(level: Int) -> UIFont {
        switch level {
        case 1:
            return .preferredFont(forTextStyle: .title2)
        case 2:
            return .preferredFont(forTextStyle: .title3)
        case 3:
            return .preferredFont(forTextStyle: .headline)
        default:
            return .preferredFont(forTextStyle: .subheadline)
        }
    }
}
