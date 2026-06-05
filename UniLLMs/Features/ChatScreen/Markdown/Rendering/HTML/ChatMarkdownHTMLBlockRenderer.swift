//
//  ChatMarkdownHTMLBlockRenderer.swift
//  UniLLMs
//
//  Native rendering for GFM raw HTML blocks.
//  Created by Zayrick on 2026/5/14.
//

import UIKit

final class ChatMarkdownHTMLBlockRenderer {
    private let context: ChatMarkdownRenderingContext

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
    }

    func renderHTMLBlock(_ rawHTML: String) -> NSMutableAttributedString {
        var state = HTMLBlockRenderingState(context: context)
        return state.render(rawHTML)
    }
}

private struct HTMLBlockRenderingState {
    private struct StackEntry {
        let tagName: String
        let mode: HTMLTextMode
    }

    private struct ListEntry {
        let isOrdered: Bool
        var nextMarker: Int
    }

    private let context: ChatMarkdownRenderingContext
    private let result = NSMutableAttributedString()
    private var mode: HTMLTextMode
    private var stack: [StackEntry] = []
    private var lists: [ListEntry] = []
    private var filteredRawHTMLTagStack: [String] = []
    private var tableCellCountInCurrentRow = 0

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
        mode = .body(context: context)
    }

    mutating func render(_ rawHTML: String) -> NSMutableAttributedString {
        for token in ChatMarkdownHTMLSupport.tokens(in: rawHTML) {
            render(token)
        }

        collapseSpacesBeforeNewlines()
        context.trimTrailingNewlines(in: result)
        if result.length > 0 {
            context.appendNewlineIfNeeded(to: result)
        }
        return result
    }

    private mutating func render(_ token: ChatMarkdownHTMLToken) {
        if !filteredRawHTMLTagStack.isEmpty {
            appendFilteredRawHTMLToken(token)
            return
        }

        switch token {
        case let .text(text), let .cdata(text):
            appendText(text)
        case .comment, .declaration, .processingInstruction:
            return
        case let .tag(tag):
            render(tag)
        }
    }

    private mutating func render(_ tag: ChatMarkdownHTMLTag) {
        if ChatMarkdownHTMLSupport.disallowedRawHTMLTagNames.contains(tag.name) {
            appendLiteral(tag.rawHTML)
            if !tag.isClosing, !tag.isSelfClosing {
                filteredRawHTMLTagStack.append(tag.name)
            }
            return
        }

        if tag.isClosing {
            close(tag.name)
            return
        }

        open(tag)
    }

    private mutating func open(_ tag: ChatMarkdownHTMLTag) {
        switch tag.name {
        case "br":
            appendLineBreak()
            return
        case "hr":
            appendHorizontalRule()
            return
        case "img":
            appendImage(tag)
            return
        case "q":
            appendRawText("\"", attributes: mode.attributes(context: context))
        case "input":
            appendInput(tag)
            return
        case "source", "track", "param", "meta", "link", "base", "col":
            return
        case "ol":
            ensureBlockBreak()
            lists.append(ListEntry(isOrdered: true, nextMarker: startIndex(for: tag)))
        case "ul", "menu", "dir":
            ensureBlockBreak()
            lists.append(ListEntry(isOrdered: false, nextMarker: 1))
        case "li":
            beginListItem()
        case "tr":
            ensureLineBreak()
            tableCellCountInCurrentRow = 0
        case "td", "th":
            beginTableCell()
        case "p", "div", "section", "article", "aside", "main", "header", "footer", "nav",
             "body", "html", "address", "figure", "figcaption", "fieldset", "form",
             "blockquote", "details", "summary", "dl", "dt", "dd", "caption", "legend",
             "center", "dialog", "search", "pre":
            ensureBlockBreak()
        default:
            if isHeading(tag.name) {
                ensureBlockBreak()
            } else if ChatMarkdownHTMLSupport.blockTagNames.contains(tag.name) {
                ensureBlockBreak()
            }
        }

        guard !tag.isSelfClosing else {
            return
        }

        let previousMode = mode
        mode = transformedMode(opening: tag, currentMode: mode)
        stack.append(StackEntry(tagName: tag.name, mode: previousMode))
    }

    private mutating func close(_ tagName: String) {
        switch tagName {
        case "ol", "ul", "menu", "dir":
            if !lists.isEmpty {
                lists.removeLast()
            }
            ensureBlockBreak()
        case "li", "tr", "p", "div", "section", "article", "aside", "main", "header",
             "footer", "nav", "body", "html", "address", "figure", "figcaption",
             "fieldset", "form", "blockquote", "details", "summary", "dl", "dt",
             "dd", "caption", "legend", "center", "dialog", "search", "pre":
            ensureBlockBreak()
        case "td", "th":
            appendSpaceIfNeeded()
        case "q":
            appendRawText("\"", attributes: mode.attributes(context: context))
        default:
            if isHeading(tagName) || ChatMarkdownHTMLSupport.blockTagNames.contains(tagName) {
                ensureBlockBreak()
            }
        }

        restoreMode(closing: tagName)
    }

    private mutating func restoreMode(closing tagName: String) {
        guard let index = stack.lastIndex(where: { $0.tagName == tagName }) else {
            return
        }

        mode = stack[index].mode
        stack.removeSubrange(index...)
    }

    private func transformedMode(opening tag: ChatMarkdownHTMLTag, currentMode: HTMLTextMode) -> HTMLTextMode {
        switch tag.name {
        case "strong", "b", "th", "summary", "dt":
            return currentMode.addingSymbolicTraits(.traitBold)
        case "em", "i", "cite", "dfn", "var", "address":
            return currentMode.addingSymbolicTraits(.traitItalic)
        case "del", "s", "strike":
            return currentMode.struckThrough()
        case "ins", "u":
            return currentMode.underlined()
        case "code", "kbd", "samp", "tt":
            return currentMode.coded()
        case "pre", "plaintext":
            return currentMode.coded().preformatted()
        case "sub":
            return currentMode.scaledFont(by: 0.82).offsetBaseline(by: -context.currentBodyFont().pointSize * 0.22)
        case "sup":
            return currentMode.scaledFont(by: 0.82).offsetBaseline(by: context.currentBodyFont().pointSize * 0.34)
        case "small":
            return currentMode.scaledFont(by: 0.86)
        case "big":
            return currentMode.scaledFont(by: 1.12)
        case "mark":
            return currentMode.marked()
        case "blockquote":
            return currentMode.quoted()
        case "center":
            return currentMode.aligned(.center)
        case "a":
            guard let href = tag.attribute("href"),
                  let url = URL(string: href) else {
                return currentMode
            }
            return currentMode.linked(to: url, color: context.style.linkColor)
        case "abbr":
            return currentMode.underlined()
        case let heading where isHeading(heading):
            return currentMode.heading(level: headingLevel(heading), context: context)
        default:
            if let alignment = alignment(from: tag.attribute("align")) {
                return currentMode.aligned(alignment)
            }
            return currentMode
        }
    }

    private func alignment(from value: String?) -> NSTextAlignment? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left":
            return .left
        case "center", "middle":
            return .center
        case "right":
            return .right
        default:
            return nil
        }
    }

    private mutating func beginListItem() {
        ensureLineBreak()

        let depth = max(0, lists.count - 1)
        appendRawText(String(repeating: "  ", count: depth), attributes: mode.attributes(context: context))

        guard var currentList = lists.popLast() else {
            appendRawText("• ", attributes: mode.attributes(context: context))
            return
        }

        if currentList.isOrdered {
            appendRawText("\(currentList.nextMarker). ", attributes: mode.attributes(context: context))
            currentList.nextMarker += 1
        } else {
            appendRawText("• ", attributes: mode.attributes(context: context))
        }
        lists.append(currentList)
    }

    private mutating func beginTableCell() {
        if tableCellCountInCurrentRow > 0 {
            appendRawText("  ", attributes: mode.attributes(context: context))
        }
        tableCellCountInCurrentRow += 1
    }

    private mutating func appendText(_ text: String) {
        var rendered = ChatMarkdownHTMLSupport.decodeEntities(in: text)
        if !mode.isPreformatted {
            rendered = ChatMarkdownHTMLSupport.collapsedWhitespace(rendered)
            rendered = trimCollapsibleLeadingWhitespace(rendered)
        }

        guard !rendered.isEmpty else {
            return
        }

        appendRawText(rendered, attributes: mode.attributes(context: context))
    }

    private func trimCollapsibleLeadingWhitespace(_ text: String) -> String {
        guard text.first == " ",
              result.string.last?.isWhitespace != false else {
            return text
        }
        return String(text.dropFirst())
    }

    private mutating func appendLiteral(_ literal: String) {
        appendRawText(literal, attributes: context.secondaryAttributes())
    }

    private mutating func appendFilteredRawHTMLToken(_ token: ChatMarkdownHTMLToken) {
        switch token {
        case let .text(text), let .cdata(text):
            appendLiteral(text)
        case let .comment(raw), let .declaration(raw), let .processingInstruction(raw):
            appendLiteral(raw)
        case let .tag(tag):
            appendLiteral(tag.rawHTML)
            if tag.isClosing, tag.name == filteredRawHTMLTagStack.last {
                filteredRawHTMLTagStack.removeLast()
            }
        }
    }

    private mutating func appendImage(_ tag: ChatMarkdownHTMLTag) {
        guard let imageBlock = ChatMarkdownHTMLSupport.imageBlock(from: tag) else {
            return
        }

        appendRawText(
            context.imageDisplayText(source: imageBlock.source, altText: imageBlock.altText),
            attributes: context.secondaryAttributes()
        )
    }

    private mutating func appendInput(_ tag: ChatMarkdownHTMLTag) {
        guard tag.attribute("type")?.lowercased() == "checkbox" else {
            return
        }

        let isChecked = tag.attributes.keys.contains("checked")
        result.appendWithChatInlineCodeVisualSpacing(checkboxAttachment(isChecked: isChecked))
    }

    private func checkboxAttachment(isChecked: Bool) -> NSAttributedString {
        ChatMarkdownCheckboxRenderer.attributedString(
            isChecked: isChecked,
            font: mode.font,
            attributes: mode.attributes(context: context)
        )
    }

    private mutating func appendHorizontalRule() {
        ensureBlockBreak()
        result.append(
            NSMutableAttributedString(
                attachment: HorizontalRuleTextAttachment(
                    color: context.style.dividerColor,
                    traitCollection: context.traitCollection
                )
            )
        )
        appendLineBreak()
    }

    private mutating func appendSpaceIfNeeded() {
        guard result.string.last?.isWhitespace != true else { return }
        appendRawText(" ", attributes: mode.attributes(context: context))
    }

    private mutating func appendLineBreak() {
        appendRawText("\n", attributes: context.bodyAttributes())
    }

    private mutating func ensureLineBreak() {
        guard !result.string.hasSuffix("\n") else { return }
        appendLineBreak()
    }

    private mutating func ensureBlockBreak() {
        ensureLineBreak()
    }

    private mutating func appendRawText(_ text: String, attributes: [NSAttributedString.Key: Any]) {
        result.appendWithChatInlineCodeVisualSpacing(
            NSAttributedString(string: text, attributes: attributes)
        )
    }

    private func startIndex(for tag: ChatMarkdownHTMLTag) -> Int {
        guard let start = tag.attribute("start"),
              let value = Int(start.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 1
        }

        return value
    }

    private func isHeading(_ tagName: String) -> Bool {
        headingLevel(tagName) != nil
    }

    private func headingLevel(_ tagName: String) -> Int? {
        guard tagName.count == 2,
              tagName.first == "h",
              let value = Int(String(tagName.dropFirst())),
              (1...6).contains(value) else {
            return nil
        }

        return value
    }

    private mutating func collapseSpacesBeforeNewlines() {
        let string = result.string as NSString
        var ranges: [NSRange] = []
        var searchStart = 0

        while searchStart < string.length {
            let searchRange = NSRange(location: searchStart, length: string.length - searchStart)
            let range = string.range(of: " \n", options: [], range: searchRange)
            guard range.location != NSNotFound else { break }

            ranges.append(range)
            searchStart = range.location + range.length
        }

        for range in ranges.reversed() {
            result.replaceCharacters(in: range, with: "\n")
        }
    }
}

private struct HTMLTextMode {
    var font: UIFont
    var foregroundColor: UIColor
    var symbolicTraits: UIFontDescriptor.SymbolicTraits
    var linkURL: URL?
    var isUnderlined: Bool
    var isStrikethrough: Bool
    var baselineOffset: CGFloat
    var backgroundColor: UIColor?
    var isCode: Bool
    var isPreformatted: Bool
    var alignment: NSTextAlignment?
    var blockQuoteDepth: Int

    static func body(context: ChatMarkdownRenderingContext) -> HTMLTextMode {
        HTMLTextMode(
            font: context.currentBodyFont(),
            foregroundColor: context.currentTextColor,
            symbolicTraits: [],
            linkURL: nil,
            isUnderlined: false,
            isStrikethrough: false,
            baselineOffset: 0.0,
            backgroundColor: nil,
            isCode: false,
            isPreformatted: false,
            alignment: nil,
            blockQuoteDepth: 0
        )
    }

    func addingSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> HTMLTextMode {
        var copy = self
        copy.symbolicTraits.formUnion(traits)
        copy.font = ChatMarkdownFontTraits.adding(traits, to: font)
        return copy
    }

    func linked(to url: URL?, color: UIColor) -> HTMLTextMode {
        var copy = self
        copy.foregroundColor = color
        copy.linkURL = url
        copy.isUnderlined = true
        return copy
    }

    func underlined() -> HTMLTextMode {
        var copy = self
        copy.isUnderlined = true
        return copy
    }

    func struckThrough() -> HTMLTextMode {
        var copy = self
        copy.isStrikethrough = true
        return copy
    }

    func coded() -> HTMLTextMode {
        var copy = self
        copy.isCode = true
        return copy
    }

    func preformatted() -> HTMLTextMode {
        var copy = self
        copy.isPreformatted = true
        return copy
    }

    func scaledFont(by scale: CGFloat) -> HTMLTextMode {
        var copy = self
        copy.font = UIFont(descriptor: font.fontDescriptor, size: max(8.0, font.pointSize * scale))
        return copy
    }

    func offsetBaseline(by offset: CGFloat) -> HTMLTextMode {
        var copy = self
        copy.baselineOffset += offset
        return copy
    }

    func marked() -> HTMLTextMode {
        var copy = self
        copy.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.35)
        return copy
    }

    func aligned(_ alignment: NSTextAlignment) -> HTMLTextMode {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    func quoted() -> HTMLTextMode {
        var copy = self
        copy.blockQuoteDepth += 1
        return copy
    }

    func heading(level: Int?, context: ChatMarkdownRenderingContext) -> HTMLTextMode {
        var copy = self
        copy.font = context.style.headingFont(level: level ?? 6, compatibleWith: context.traitCollection)
        copy.symbolicTraits = copy.font.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic])
        return copy
    }

    func attributes(context: ChatMarkdownRenderingContext) -> [NSAttributedString.Key: Any] {
        let resolvedFont: UIFont
        if isCode {
            resolvedFont = ChatMarkdownFontTraits.adding(
                symbolicTraits,
                to: context.style.codeFont(compatibleWith: context.traitCollection)
            )
        } else {
            resolvedFont = font
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont,
            .foregroundColor: foregroundColor
        ]

        if isCode {
            attributes[.chatInlineCodeBackgroundColor] = context.style.codeBackgroundColor
            attributes[.chatInlineCodeCornerRadius] = ChatMarkdownInlineCodeStyle.cornerRadius
        }
        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }
        if alignment != nil || blockQuoteDepth > 0 {
            attributes[.paragraphStyle] = paragraphStyle(context: context)
        }
        if blockQuoteDepth > 0 {
            attributes[.chatBlockQuoteBarPositions] = blockQuoteBarPositions
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

    private func paragraphStyle(context: ChatMarkdownRenderingContext) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = context.style.bodyLineSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacing = blockQuoteDepth > 0
            ? context.style.blockQuoteParagraphSpacing(compatibleWith: context.traitCollection)
            : context.style.bodyParagraphSpacing(compatibleWith: context.traitCollection)
        if let alignment {
            paragraphStyle.alignment = alignment
        }
        if blockQuoteDepth > 0 {
            let indent = CGFloat(blockQuoteDepth) * ChatMarkdownBlockQuoteStyle.indentPerLevel
            paragraphStyle.firstLineHeadIndent = indent
            paragraphStyle.headIndent = indent
        }
        return paragraphStyle
    }

    private var blockQuoteBarPositions: [CGFloat] {
        guard blockQuoteDepth > 0 else {
            return []
        }

        return (0..<blockQuoteDepth).map { depth in
            ChatMarkdownBlockQuoteStyle.barLeading + CGFloat(depth) * ChatMarkdownBlockQuoteStyle.indentPerLevel
        }
    }
}
