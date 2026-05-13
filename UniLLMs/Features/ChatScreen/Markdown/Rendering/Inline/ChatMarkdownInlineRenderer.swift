//
//  ChatMarkdownInlineRenderer.swift
//  UniLLMs
//
//  Inline Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

private struct ChatMarkdownInlineRenderingMode {
    private static let composableFontTraits: UIFontDescriptor.SymbolicTraits = [
        .traitBold,
        .traitItalic
    ]

    var font: UIFont
    var foregroundColor: UIColor
    var symbolicTraits: UIFontDescriptor.SymbolicTraits
    var linkURL: URL?
    var isUnderlined: Bool
    var isStrikethrough: Bool

    static func body(context: ChatMarkdownRenderingContext) -> ChatMarkdownInlineRenderingMode {
        base(
            font: context.currentBodyFont(),
            foregroundColor: context.currentTextColor
        )
    }

    static func base(font: UIFont, foregroundColor: UIColor) -> ChatMarkdownInlineRenderingMode {
        ChatMarkdownInlineRenderingMode(
            font: font,
            foregroundColor: foregroundColor,
            symbolicTraits: font.fontDescriptor.symbolicTraits.intersection(composableFontTraits),
            linkURL: nil,
            isUnderlined: false,
            isStrikethrough: false
        )
    }

    func addingSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.symbolicTraits.formUnion(traits)
        copy.font = ChatMarkdownFontTraits.adding(traits, to: font)
        return copy
    }

    func linked(to url: URL?, color: UIColor) -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.foregroundColor = color
        copy.linkURL = url
        copy.isUnderlined = true
        return copy
    }

    func struckThrough() -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.isStrikethrough = true
        return copy
    }

    func attributes() -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor
        ]

        if isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let linkURL {
            attributes[.link] = linkURL
        }

        return attributes
    }
}

final class ChatMarkdownInlineRenderer {
    private let context: ChatMarkdownRenderingContext
    private let inlineCodeRenderer: ChatMarkdownInlineCodeRenderer
    private let visibleTextExtractor: ChatMarkdownVisibleTextExtractor

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
        inlineCodeRenderer = ChatMarkdownInlineCodeRenderer(context: context)
        visibleTextExtractor = ChatMarkdownVisibleTextExtractor(context: context)
    }

    func renderChildren(of markup: any Markup) -> NSMutableAttributedString {
        renderChildren(of: markup, mode: .body(context: context))
    }

    func renderChildren(
        of markup: any Markup,
        font: UIFont,
        foregroundColor: UIColor
    ) -> NSMutableAttributedString {
        renderChildren(
            of: markup,
            mode: .base(font: font, foregroundColor: foregroundColor)
        )
    }

    private func renderChildren(
        of markup: any Markup,
        mode: ChatMarkdownInlineRenderingMode
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let children = Array(markup.children)

        for (index, child) in children.enumerated() {
            if let inlineCode = child as? InlineCode {
                result.append(
                    inlineCodeRenderer.render(
                        inlineCode,
                        mode: mode,
                        needsLeadingMargin: inlineCodeRenderer.needsMargin(before: result.string.last),
                        needsTrailingMargin: inlineCodeRenderer.needsMargin(
                            after: visibleTextExtractor.firstVisibleCharacter(after: index, in: children)
                        )
                    )
                )
            } else {
                result.append(render(child, mode: mode))
            }
        }

        return result
    }

    private func render(
        _ markup: any Markup,
        mode: ChatMarkdownInlineRenderingMode
    ) -> NSMutableAttributedString {
        switch markup {
        case let text as Text:
            return NSMutableAttributedString(string: text.string, attributes: mode.attributes())
        case let strong as Strong:
            return renderChildren(
                of: strong,
                mode: mode.addingSymbolicTraits(.traitBold)
            )
        case let emphasis as Emphasis:
            return renderChildren(
                of: emphasis,
                mode: mode.addingSymbolicTraits(.traitItalic)
            )
        case let strikethrough as Strikethrough:
            return renderChildren(of: strikethrough, mode: mode.struckThrough())
        case let inlineCode as InlineCode:
            return inlineCodeRenderer.render(
                inlineCode,
                mode: mode,
                needsLeadingMargin: false,
                needsTrailingMargin: false
            )
        case let link as Link:
            return renderChildren(
                of: link,
                mode: mode.linked(
                    to: link.destination.flatMap { URL(string: $0) },
                    color: context.style.linkColor
                )
            )
        case let image as Markdown.Image:
            return NSMutableAttributedString(
                string: context.imageDisplayText(source: image.source, altText: image.plainText),
                attributes: context.secondaryAttributes()
            )
        case _ as SoftBreak:
            return NSMutableAttributedString(string: " ", attributes: mode.attributes())
        case _ as LineBreak:
            return NSMutableAttributedString(string: "\n", attributes: mode.attributes())
        case let html as InlineHTML:
            return NSMutableAttributedString(string: html.rawHTML, attributes: context.secondaryAttributes())
        default:
            return renderChildren(of: markup, mode: mode)
        }
    }
}

private final class ChatMarkdownInlineCodeRenderer {
    private let context: ChatMarkdownRenderingContext

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
    }

    func render(
        _ inlineCode: InlineCode,
        mode: ChatMarkdownInlineRenderingMode,
        needsLeadingMargin: Bool,
        needsTrailingMargin: Bool
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        if needsLeadingMargin {
            result.append(
                NSAttributedString(
                    string: ChatMarkdownInlineCodeStyle.outerMargin,
                    attributes: mode.attributes()
                )
            )
        }

        result.append(
            NSAttributedString(
                string: inlineCode.code,
                attributes: attributes(mode: mode)
            )
        )

        if needsTrailingMargin {
            result.append(
                NSAttributedString(
                    string: ChatMarkdownInlineCodeStyle.outerMargin,
                    attributes: mode.attributes()
                )
            )
        }

        return result
    }

    func needsMargin(before character: Character?) -> Bool {
        guard let character else {
            return false
        }

        return !isMarginBoundary(character)
    }

    func needsMargin(after character: Character?) -> Bool {
        guard let character else {
            return false
        }

        return !isMarginBoundary(character)
    }

    private func attributes(mode: ChatMarkdownInlineRenderingMode) -> [NSAttributedString.Key: Any] {
        let codeFont = context.style.codeFont(compatibleWith: context.traitCollection)
        let resolvedCodeFont = ChatMarkdownFontTraits.adding(mode.symbolicTraits, to: codeFont)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedCodeFont,
            .foregroundColor: context.style.codeTextColor,
            .chatInlineCodeBackgroundColor: context.style.codeBackgroundColor,
            .chatInlineCodeCornerRadius: ChatMarkdownInlineCodeStyle.cornerRadius
        ]

        if mode.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if mode.isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let linkURL = mode.linkURL {
            attributes[.link] = linkURL
        }

        return attributes
    }

    private func isMarginBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

private final class ChatMarkdownVisibleTextExtractor {
    private let context: ChatMarkdownRenderingContext

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
    }

    func firstVisibleCharacter(after index: Int, in children: [any Markup]) -> Character? {
        guard index + 1 < children.count else {
            return nil
        }

        for child in children[(index + 1)...] {
            if let character = visibleText(in: child).first {
                return character
            }
        }

        return nil
    }

    private func visibleText(in markup: any Markup) -> String {
        switch markup {
        case let text as Text:
            return text.string
        case let inlineCode as InlineCode:
            return inlineCode.code
        case let image as Markdown.Image:
            return context.imageDisplayText(source: image.source, altText: image.plainText)
        case _ as SoftBreak:
            return " "
        case _ as LineBreak:
            return "\n"
        case let html as InlineHTML:
            return html.rawHTML
        default:
            var result = ""
            for child in markup.children {
                result += visibleText(in: child)
            }
            return result
        }
    }
}
