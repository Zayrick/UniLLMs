//
//  ChatMarkdownInlineRenderer.swift
//  UniLLMs
//
//  Inline Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Foundation
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
    var baselineOffset: CGFloat
    var backgroundColor: UIColor?
    var isCode: Bool

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
            isStrikethrough: false,
            baselineOffset: 0.0,
            backgroundColor: nil,
            isCode: false
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

    func underlined() -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.isUnderlined = true
        return copy
    }

    func struckThrough() -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.isStrikethrough = true
        return copy
    }

    func coded() -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.isCode = true
        return copy
    }

    func scaledFont(by scale: CGFloat) -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.font = UIFont(descriptor: font.fontDescriptor, size: max(8.0, font.pointSize * scale))
        return copy
    }

    func offsetBaseline(by offset: CGFloat) -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.baselineOffset += offset
        return copy
    }

    func marked() -> ChatMarkdownInlineRenderingMode {
        var copy = self
        copy.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.35)
        return copy
    }

    func attributes() -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor
        ]

        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }
        if isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if baselineOffset != 0.0 {
            attributes[.baselineOffset] = baselineOffset
        }
        if let linkURL {
            attributes[.link] = linkURL
        }
        ChatMarkdownFontTraits.applyItalicObliquenessIfNeeded(
            to: &attributes,
            requestedTraits: symbolicTraits
        )

        return attributes
    }

    func inlineCodeAttributes(context: ChatMarkdownRenderingContext) -> [NSAttributedString.Key: Any] {
        let codeFont = context.style.codeFont(compatibleWith: context.traitCollection)
        let resolvedCodeFont = ChatMarkdownFontTraits.adding(symbolicTraits, to: codeFont)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedCodeFont,
            .foregroundColor: context.style.codeTextColor,
            .chatInlineCodeBackgroundColor: context.style.codeBackgroundColor,
            .chatInlineCodeCornerRadius: ChatMarkdownInlineCodeStyle.cornerRadius
        ]

        if isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if baselineOffset != 0.0 {
            attributes[.baselineOffset] = baselineOffset
        }
        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }
        if let linkURL {
            attributes[.link] = linkURL
        }
        ChatMarkdownFontTraits.applyItalicObliquenessIfNeeded(
            to: &attributes,
            requestedTraits: symbolicTraits
        )

        return attributes
    }
}

final class ChatMarkdownInlineRenderer {
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private let context: ChatMarkdownRenderingContext
    private let inlineCodeRenderer: ChatMarkdownInlineCodeRenderer

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
        inlineCodeRenderer = ChatMarkdownInlineCodeRenderer(context: context)
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
        var htmlState = ChatMarkdownInlineHTMLState(mode: mode, context: context)

        for child in children {
            let activeMode = htmlState.mode
            let renderedChild: NSAttributedString
            if let html = child as? InlineHTML {
                renderedChild = htmlState.render(html.rawHTML)
            } else if let inlineCode = child as? InlineCode {
                renderedChild = inlineCodeRenderer.render(inlineCode, mode: activeMode)
            } else {
                renderedChild = render(child, mode: activeMode)
            }
            result.appendWithChatInlineCodeVisualSpacing(renderedChild)
        }

        return result
    }

    private func render(
        _ markup: any Markup,
        mode: ChatMarkdownInlineRenderingMode
    ) -> NSMutableAttributedString {
        switch markup {
        case let text as Text:
            if mode.isCode {
                return inlineCodeRenderer.renderText(text.string, mode: mode)
            }
            return renderText(text.string, mode: mode)
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
            return inlineCodeRenderer.render(inlineCode, mode: mode)
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
            var htmlState = ChatMarkdownInlineHTMLState(mode: mode, context: context)
            return htmlState.render(html.rawHTML)
        default:
            return renderChildren(of: markup, mode: mode)
        }
    }

    private func renderText(
        _ text: String,
        mode: ChatMarkdownInlineRenderingMode
    ) -> NSMutableAttributedString {
        let spans = ChatMarkdownMathDelimiterScanner.inlineSpans(in: text)
        guard !spans.isEmpty else {
            return renderPlainText(text, mode: mode)
        }

        let result = NSMutableAttributedString()
        var cursor = text.startIndex

        for span in spans {
            if cursor < span.range.lowerBound {
                result.append(renderPlainText(String(text[cursor..<span.range.lowerBound]), mode: mode))
            }

            if let renderedImage = ChatMarkdownMathImageRenderer.renderInline(
                latex: span.latex,
                font: mode.font,
                textColor: mode.foregroundColor,
                traitCollection: context.traitCollection
            ) {
                let attachment = NSMutableAttributedString(
                    attachment: ChatMarkdownMathTextAttachment(renderedImage: renderedImage)
                )
                var attributes = mode.attributes()
                attributes[.chatAccessibilityText] = String(localized: .markdownFormulaFormat(span.latex))
                attachment.addAttributes(
                    attributes,
                    range: NSRange(location: 0, length: attachment.length)
                )
                result.append(attachment)
            } else {
                result.append(
                    NSAttributedString(
                        string: String(text[span.range]),
                        attributes: mode.attributes()
                    )
                )
            }

            cursor = span.range.upperBound
        }

        if cursor < text.endIndex {
            result.append(renderPlainText(String(text[cursor..<text.endIndex]), mode: mode))
        }

        return result
    }

    private func renderPlainText(
        _ text: String,
        mode: ChatMarkdownInlineRenderingMode
    ) -> NSMutableAttributedString {
        guard !text.isEmpty else {
            return NSMutableAttributedString()
        }
        guard mode.linkURL == nil,
              !mode.isCode,
              let linkDetector = Self.linkDetector else {
            return NSMutableAttributedString(string: text, attributes: mode.attributes())
        }

        let result = NSMutableAttributedString()
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var cursor = text.startIndex

        for match in linkDetector.matches(in: text, options: [], range: fullRange) {
            guard match.resultType == .link,
                  let url = match.url,
                  let matchRange = Range(match.range, in: text) else {
                continue
            }

            if cursor < matchRange.lowerBound {
                result.append(
                    NSAttributedString(
                        string: String(text[cursor..<matchRange.lowerBound]),
                        attributes: mode.attributes()
                    )
                )
            }

            result.append(
                NSAttributedString(
                    string: String(text[matchRange]),
                    attributes: mode.linked(to: url, color: context.style.linkColor).attributes()
                )
            )
            cursor = matchRange.upperBound
        }

        if cursor < text.endIndex {
            result.append(
                NSAttributedString(
                    string: String(text[cursor..<text.endIndex]),
                    attributes: mode.attributes()
                )
            )
        }

        return result
    }
}

private final class ChatMarkdownInlineCodeRenderer {
    private let context: ChatMarkdownRenderingContext

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
    }

    func render(
        _ inlineCode: InlineCode,
        mode: ChatMarkdownInlineRenderingMode
    ) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: inlineCode.code,
            attributes: attributes(mode: mode)
        )
    }

    func renderText(
        _ text: String,
        mode: ChatMarkdownInlineRenderingMode
    ) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text,
            attributes: attributes(mode: mode)
        )
    }

    private func attributes(mode: ChatMarkdownInlineRenderingMode) -> [NSAttributedString.Key: Any] {
        mode.inlineCodeAttributes(context: context)
    }
}

private struct ChatMarkdownInlineHTMLState {
    private struct StackEntry {
        let tagName: String
        let mode: ChatMarkdownInlineRenderingMode
    }

    private let context: ChatMarkdownRenderingContext
    private var stack: [StackEntry] = []
    private var filteredRawHTMLTagStack: [String] = []
    var mode: ChatMarkdownInlineRenderingMode

    init(mode: ChatMarkdownInlineRenderingMode, context: ChatMarkdownRenderingContext) {
        self.mode = mode
        self.context = context
    }

    mutating func render(_ rawHTML: String) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for token in ChatMarkdownHTMLSupport.tokens(in: rawHTML) {
            if !filteredRawHTMLTagStack.isEmpty {
                result.appendWithChatInlineCodeVisualSpacing(renderFilteredRawHTMLToken(token))
                continue
            }

            switch token {
            case let .text(text), let .cdata(text):
                let attributes = mode.isCode
                    ? mode.inlineCodeAttributes(context: context)
                    : mode.attributes()
                result.appendWithChatInlineCodeVisualSpacing(
                    NSAttributedString(
                        string: ChatMarkdownHTMLSupport.decodeEntities(in: text),
                        attributes: attributes
                    )
                )
            case .comment, .declaration, .processingInstruction:
                continue
            case let .tag(tag):
                result.appendWithChatInlineCodeVisualSpacing(render(tag))
            }
        }

        return result
    }

    private mutating func render(_ tag: ChatMarkdownHTMLTag) -> NSAttributedString {
        if ChatMarkdownHTMLSupport.disallowedRawHTMLTagNames.contains(tag.name) {
            if !tag.isClosing, !tag.isSelfClosing {
                filteredRawHTMLTagStack.append(tag.name)
            }
            return NSAttributedString(string: tag.rawHTML, attributes: context.secondaryAttributes())
        }

        if tag.isClosing {
            if tag.name == "q" {
                restoreMode(closing: tag.name)
                return NSAttributedString(string: "\"", attributes: mode.attributes())
            }
            restoreMode(closing: tag.name)
            return NSAttributedString()
        }

        switch tag.name {
        case "br":
            return NSAttributedString(string: "\n", attributes: mode.attributes())
        case "img":
            guard let imageBlock = ChatMarkdownHTMLSupport.imageBlock(from: tag) else {
                return NSAttributedString()
            }
            return NSAttributedString(
                string: context.imageDisplayText(source: imageBlock.source, altText: imageBlock.altText),
                attributes: context.secondaryAttributes()
            )
        case "input":
            guard tag.attribute("type")?.lowercased() == "checkbox" else {
                return NSAttributedString()
            }
            let isChecked = tag.attributes.keys.contains("checked")
            return checkboxAttachment(isChecked: isChecked)
        case "q":
            let quote = NSAttributedString(string: "\"", attributes: mode.attributes())
            guard !tag.isSelfClosing else {
                return quote
            }
            let previousMode = mode
            stack.append(StackEntry(tagName: tag.name, mode: previousMode))
            return quote
        case "source", "track", "param", "meta", "link", "base", "col", "wbr":
            return NSAttributedString()
        default:
            break
        }

        guard !tag.isSelfClosing else {
            return NSAttributedString()
        }

        let previousMode = mode
        mode = transformedMode(opening: tag)
        stack.append(StackEntry(tagName: tag.name, mode: previousMode))
        return NSAttributedString()
    }

    private mutating func renderFilteredRawHTMLToken(_ token: ChatMarkdownHTMLToken) -> NSAttributedString {
        switch token {
        case let .text(text), let .cdata(text):
            return NSAttributedString(string: text, attributes: context.secondaryAttributes())
        case let .comment(raw), let .declaration(raw), let .processingInstruction(raw):
            return NSAttributedString(string: raw, attributes: context.secondaryAttributes())
        case let .tag(tag):
            if tag.isClosing, tag.name == filteredRawHTMLTagStack.last {
                filteredRawHTMLTagStack.removeLast()
            }
            return NSAttributedString(string: tag.rawHTML, attributes: context.secondaryAttributes())
        }
    }

    private func checkboxAttachment(isChecked: Bool) -> NSAttributedString {
        ChatMarkdownCheckboxRenderer.attributedString(
            isChecked: isChecked,
            font: mode.font,
            attributes: mode.attributes()
        )
    }

    private mutating func restoreMode(closing tagName: String) {
        guard let index = stack.lastIndex(where: { $0.tagName == tagName }) else {
            return
        }

        mode = stack[index].mode
        stack.removeSubrange(index...)
    }

    private func transformedMode(opening tag: ChatMarkdownHTMLTag) -> ChatMarkdownInlineRenderingMode {
        switch tag.name {
        case "strong", "b":
            return mode.addingSymbolicTraits(.traitBold)
        case "em", "i", "cite", "dfn", "var":
            return mode.addingSymbolicTraits(.traitItalic)
        case "del", "s", "strike":
            return mode.struckThrough()
        case "ins", "u":
            return mode.underlined()
        case "code", "kbd", "samp", "tt":
            return mode.coded()
        case "sub":
            return mode.scaledFont(by: 0.82).offsetBaseline(by: -context.currentBodyFont().pointSize * 0.22)
        case "sup":
            return mode.scaledFont(by: 0.82).offsetBaseline(by: context.currentBodyFont().pointSize * 0.34)
        case "small":
            return mode.scaledFont(by: 0.86)
        case "big":
            return mode.scaledFont(by: 1.12)
        case "mark":
            return mode.marked()
        case "a":
            guard let href = tag.attribute("href"),
                  let url = URL(string: href) else {
                return mode
            }
            return mode.linked(
                to: url,
                color: context.style.linkColor
            )
        case "abbr":
            return mode.underlined()
        default:
            return mode
        }
    }
}
