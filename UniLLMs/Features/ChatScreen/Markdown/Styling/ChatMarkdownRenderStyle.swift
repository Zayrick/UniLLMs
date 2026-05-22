//
//  ChatMarkdownRenderStyle.swift
//  UniLLMs
//
//  Style values for chat Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import UIKit

struct ChatMarkdownRenderStyle {
    enum HeadingScale {
        case standard
        case compact
    }

    var textColor: UIColor
    var secondaryTextColor: UIColor
    var linkColor: UIColor
    var codeTextColor: UIColor
    var codeBackgroundColor: UIColor
    var codeBlockBackgroundColor: UIColor
    var bodyTextStyle: UIFont.TextStyle
    var secondaryTextStyle: UIFont.TextStyle
    var codeTextStyle: UIFont.TextStyle
    var headingScale: HeadingScale

    init(
        textColor: UIColor,
        secondaryTextColor: UIColor,
        linkColor: UIColor,
        codeTextColor: UIColor,
        codeBackgroundColor: UIColor,
        codeBlockBackgroundColor: UIColor,
        bodyTextStyle: UIFont.TextStyle = .body,
        secondaryTextStyle: UIFont.TextStyle = .callout,
        codeTextStyle: UIFont.TextStyle = .callout,
        headingScale: HeadingScale = .standard
    ) {
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.codeTextColor = codeTextColor
        self.codeBackgroundColor = codeBackgroundColor
        self.codeBlockBackgroundColor = codeBlockBackgroundColor
        self.bodyTextStyle = bodyTextStyle
        self.secondaryTextStyle = secondaryTextStyle
        self.codeTextStyle = codeTextStyle
        self.headingScale = headingScale
    }

    static var assistant: ChatMarkdownRenderStyle {
        ChatMarkdownRenderStyle(
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .systemBlue,
            codeTextColor: .label,
            codeBackgroundColor: .secondarySystemFill,
            codeBlockBackgroundColor: .quaternarySystemFill
        )
    }

    static var thinking: ChatMarkdownRenderStyle {
        ChatMarkdownRenderStyle(
            textColor: .secondaryLabel,
            secondaryTextColor: .tertiaryLabel,
            linkColor: .secondaryLabel,
            codeTextColor: .secondaryLabel,
            codeBackgroundColor: .tertiarySystemFill,
            codeBlockBackgroundColor: .quaternarySystemFill,
            bodyTextStyle: .footnote,
            secondaryTextStyle: .footnote,
            codeTextStyle: .footnote,
            headingScale: .compact
        )
    }

    func bodyFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        .preferredFont(forTextStyle: bodyTextStyle, compatibleWith: traitCollection)
    }

    func calloutFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        .preferredFont(forTextStyle: secondaryTextStyle, compatibleWith: traitCollection)
    }

    func codeFont(compatibleWith traitCollection: UITraitCollection) -> UIFont {
        .monospacedSystemFont(
            ofSize: UIFont.preferredFont(
                forTextStyle: codeTextStyle,
                compatibleWith: traitCollection
            ).pointSize,
            weight: .regular
        )
    }

    var dividerColor: UIColor {
        secondaryTextColor.withAlphaComponent(0.35)
    }

    func headingFont(level: Int, compatibleWith traitCollection: UITraitCollection) -> UIFont {
        let font = UIFont.preferredFont(
            forTextStyle: headingTextStyle(level: level),
            compatibleWith: traitCollection
        )
        return ChatMarkdownFontTraits.adding(headingTraits(level: level), to: font)
    }

    func bodyLineSpacing(compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemLineSpacing(for: bodyFont(compatibleWith: traitCollection))
    }

    func compactLineSpacing(compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemLineSpacing(for: calloutFont(compatibleWith: traitCollection))
    }

    func codeLineSpacing(compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemLineSpacing(for: codeFont(compatibleWith: traitCollection))
    }

    func bodyParagraphSpacing(compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemParagraphSpacing(for: bodyFont(compatibleWith: traitCollection))
    }

    func listItemSpacing(compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemParagraphSpacing(for: bodyFont(compatibleWith: traitCollection))
    }

    func blockQuoteParagraphSpacing(compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemParagraphSpacing(for: bodyFont(compatibleWith: traitCollection))
    }

    func headingLineSpacing(level: Int, compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemLineSpacing(for: headingFont(level: level, compatibleWith: traitCollection))
    }

    func headingParagraphSpacingBefore(level: Int, compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemParagraphSpacing(for: headingFont(level: level, compatibleWith: traitCollection))
    }

    func headingParagraphSpacingAfter(level: Int, compatibleWith traitCollection: UITraitCollection) -> CGFloat {
        systemParagraphSpacing(for: headingFont(level: level, compatibleWith: traitCollection))
    }

    private func headingTextStyle(level: Int) -> UIFont.TextStyle {
        if headingScale == .compact {
            return bodyTextStyle
        }

        switch level {
        case 1:
            return .title1
        case 2:
            return .title2
        case 3:
            return .title3
        case 4:
            return .headline
        case 5:
            return .subheadline
        default:
            return .footnote
        }
    }

    private func headingTraits(level: Int) -> UIFontDescriptor.SymbolicTraits {
        if headingScale == .compact {
            return .traitBold
        }

        return level == 4 ? UIFontDescriptor.SymbolicTraits() : .traitBold
    }

    private func systemParagraphSpacing(for font: UIFont) -> CGFloat {
        ceil(max(font.leading, font.lineHeight - font.pointSize))
    }

    private func systemLineSpacing(for font: UIFont) -> CGFloat {
        ceil(max(font.leading, font.lineHeight - font.pointSize))
    }
}
