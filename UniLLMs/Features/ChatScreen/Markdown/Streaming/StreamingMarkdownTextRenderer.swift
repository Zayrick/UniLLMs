//
//  StreamingMarkdownTextRenderer.swift
//  UniLLMs
//
//  Lightweight open-block Markdown renderer for the streaming hot path.
//  Closed blocks still use swift-markdown for full CommonMark/GFM fidelity;
//  this renderer keeps still-open text incremental and stable while tokens are
//  arriving character by character.
//
//  Created by Codex on 2026/5/21.
//

import UIKit

final class StreamingMarkdownTextRenderer {
    private let context: ChatMarkdownRenderingContext
    private let inlineRenderer: StreamingMarkdownInlineRenderer

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
        inlineRenderer = StreamingMarkdownInlineRenderer(context: context)
    }

    func render(rawMarkdown: String, isOpen: Bool) -> NSMutableAttributedString {
        let lines = Self.displayLines(in: rawMarkdown)
        let parsedLines = lines.map(Self.renderLine)
        let listColumnWidths = listMarkerColumnWidths(in: parsedLines)
        let result = NSMutableAttributedString()
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: " ")
            let paragraph = inlineRenderer.render(text, allowPrediction: isOpen)
            context.appendNewlineIfNeeded(to: paragraph)
            context.applyParagraphStyle(to: paragraph)
            result.append(paragraph)
            paragraphLines.removeAll()
        }

        var index = parsedLines.startIndex
        while index < parsedLines.endIndex {
            let line = parsedLines[index]
            switch line {
            case .blank:
                flushParagraph()

            case let .heading(heading):
                flushParagraph()
                result.append(renderHeading(heading, allowPrediction: isOpen))

            case let .blockQuote(quote):
                flushParagraph()
                var quoteLines = [quote]
                var nextIndex = parsedLines.index(after: index)
                while nextIndex < parsedLines.endIndex,
                      case let .blockQuote(nextQuote) = parsedLines[nextIndex] {
                    quoteLines.append(nextQuote)
                    nextIndex = parsedLines.index(after: nextIndex)
                }
                result.append(renderBlockQuote(quoteLines, allowPrediction: isOpen))
                index = nextIndex
                continue

            case let .listItem(item):
                flushParagraph()
                let columnWidth = listColumnWidths[item.columnKey] ?? ListLayout.markerMinWidth
                result.append(
                    renderListItem(
                        item,
                        markerColumnWidth: columnWidth,
                        allowPrediction: isOpen
                    )
                )

            case let .paragraph(text):
                paragraphLines.append(text)
            }

            index = parsedLines.index(after: index)
        }

        flushParagraph()
        return result
    }

    private func renderHeading(
        _ heading: HeadingLine,
        allowPrediction: Bool
    ) -> NSMutableAttributedString {
        let attributed = inlineRenderer.render(
            heading.text,
            font: context.style.headingFont(level: heading.level, compatibleWith: context.traitCollection),
            foregroundColor: context.currentTextColor,
            allowPrediction: allowPrediction
        )
        context.appendNewlineIfNeeded(to: attributed)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = context.style.headingLineSpacing(
            level: heading.level,
            compatibleWith: context.traitCollection
        )
        paragraphStyle.paragraphSpacingBefore = context.style.headingParagraphSpacingBefore(
            level: heading.level,
            compatibleWith: context.traitCollection
        )
        paragraphStyle.paragraphSpacing = context.style.headingParagraphSpacingAfter(
            level: heading.level,
            compatibleWith: context.traitCollection
        )
        context.apply([.paragraphStyle: paragraphStyle], to: attributed)
        return attributed
    }

    private func renderBlockQuote(
        _ quotes: [BlockQuoteLine],
        allowPrediction: Bool
    ) -> NSMutableAttributedString {
        guard let minimumDepth = quotes.map(\.depth).min() else {
            return NSMutableAttributedString()
        }

        let innerMarkdown = normalizedBlockQuoteInnerMarkdown(
            quotes,
            removingDepth: minimumDepth
        )
        let attributed = StreamingMarkdownTextRenderer(context: context).render(
            rawMarkdown: innerMarkdown,
            isOpen: allowPrediction
        )
        context.trimTrailingNewlines(in: attributed)
        if attributed.length == 0 {
            context.appendNewlineIfNeeded(to: attributed)
        }
        context.offsetParagraphIndent(
            in: attributed,
            by: CGFloat(minimumDepth) * ChatMarkdownBlockQuoteStyle.indentPerLevel,
            minimumParagraphSpacing: context.style.blockQuoteParagraphSpacing(
                compatibleWith: context.traitCollection
            )
        )
        addBlockQuoteBars(to: attributed, depth: minimumDepth)
        context.appendNewlineIfNeeded(to: attributed)
        return attributed
    }

    private func normalizedBlockQuoteInnerMarkdown(
        _ quotes: [BlockQuoteLine],
        removingDepth minimumDepth: Int
    ) -> String {
        quotes
            .map { quote in
                let remainingDepth = max(0, quote.depth - minimumDepth)
                guard remainingDepth > 0 else {
                    return quote.text
                }

                let prefix = String(repeating: "> ", count: remainingDepth)
                return prefix + quote.text
            }
            .joined(separator: "\n")
    }

    private func addBlockQuoteBars(to attributed: NSMutableAttributedString, depth: Int) {
        guard attributed.length > 0, depth > 0 else {
            return
        }

        let positions = (0..<depth).map { index in
            ChatMarkdownBlockQuoteStyle.barLeading
                + CGFloat(index) * ChatMarkdownBlockQuoteStyle.indentPerLevel
        }
        let fullRange = NSRange(location: 0, length: attributed.length)
        var updates: [(positions: [CGFloat], range: NSRange)] = []
        attributed.enumerateAttribute(.chatBlockQuoteBarPositions, in: fullRange) { value, range, _ in
            let existingPositions = (value as? [CGFloat]) ?? []
            updates.append((mergedBlockQuoteBarPositions(existingPositions, positions), range))
        }

        for update in updates {
            attributed.addAttribute(
                .chatBlockQuoteBarPositions,
                value: update.positions,
                range: update.range
            )
        }
    }

    private func mergedBlockQuoteBarPositions(_ lhs: [CGFloat], _ rhs: [CGFloat]) -> [CGFloat] {
        var result = lhs
        for position in rhs where !result.contains(position) {
            result.append(position)
        }
        return result.sorted()
    }

    private func renderListItem(
        _ item: ListItemLine,
        markerColumnWidth: CGFloat,
        allowPrediction: Bool
    ) -> NSMutableAttributedString {
        let attributed = markerAttributedString(item.marker, isOrdered: item.isOrdered)
        attributed.append(inlineRenderer.render(item.text, allowPrediction: allowPrediction))
        context.appendNewlineIfNeeded(to: attributed)

        let baseIndent = CGFloat(item.indentLevel) * ListLayout.indent
        let markerWidth = markerWidth(item.marker, isOrdered: item.isOrdered)
        let contentIndent = baseIndent + markerColumnWidth + ListLayout.markerSpacing
        let markerIndent = max(
            baseIndent,
            contentIndent - ListLayout.markerSpacing - markerWidth
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = context.style.bodyLineSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.firstLineHeadIndent = markerIndent
        paragraphStyle.headIndent = contentIndent
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .left, location: contentIndent)
        ]
        paragraphStyle.paragraphSpacing = context.style.listItemSpacing(compatibleWith: context.traitCollection)
        context.apply([.paragraphStyle: paragraphStyle], to: attributed)
        return attributed
    }

    private func listMarkerColumnWidths(in lines: [RenderLine]) -> [ListColumnKey: CGFloat] {
        var widths: [ListColumnKey: CGFloat] = [:]
        for line in lines {
            guard case let .listItem(item) = line else { continue }
            let width = max(
                ListLayout.markerMinWidth,
                markerWidth(item.marker, isOrdered: item.isOrdered)
            )
            widths[item.columnKey] = max(widths[item.columnKey] ?? 0.0, width)
        }
        return widths
    }

    private func markerAttributedString(
        _ marker: ListMarker,
        isOrdered: Bool
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        switch marker {
        case let .text(text):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: listMarkerFont(isOrdered: isOrdered),
                .foregroundColor: context.currentTextColor
            ]
            result.append(NSAttributedString(string: text, attributes: attributes))
        case let .symbol(name):
            if let image = symbolImage(named: name) {
                let symbol = NSMutableAttributedString(attachment: NSTextAttachment(image: image))
                symbol.addAttributes(context.bodyAttributes(), range: NSRange(location: 0, length: symbol.length))
                result.append(symbol)
            }
        }
        result.append(NSAttributedString(string: "\t", attributes: context.bodyAttributes()))
        return result
    }

    private func markerWidth(_ marker: ListMarker, isOrdered: Bool) -> CGFloat {
        switch marker {
        case let .text(text):
            return ceil((text as NSString).size(withAttributes: [.font: listMarkerFont(isOrdered: isOrdered)]).width)
        case let .symbol(name):
            return symbolImage(named: name)?.size.width ?? 0.0
        }
    }

    private func listMarkerFont(isOrdered: Bool) -> UIFont {
        guard isOrdered else {
            return context.currentBodyFont()
        }

        return .monospacedDigitSystemFont(
            ofSize: context.currentBodyFont().pointSize,
            weight: .regular
        )
    }

    private func symbolImage(named name: String) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: context.currentBodyFont(), scale: .medium)
        return UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(
                context.currentTextColor.resolvedColor(with: context.traitCollection),
                renderingMode: .alwaysOriginal
            )
    }
}

private extension StreamingMarkdownTextRenderer {
    private enum ListLayout {
        static let indent: CGFloat = 24.0
        static let markerMinWidth: CGFloat = 20.0
        static let markerSpacing: CGFloat = 6.0
    }

    enum RenderLine {
        case blank
        case heading(HeadingLine)
        case blockQuote(BlockQuoteLine)
        case listItem(ListItemLine)
        case paragraph(String)
    }

    enum ListMarker: Hashable {
        case text(String)
        case symbol(name: String)
    }

    struct ListColumnKey: Hashable {
        let indentLevel: Int
        let isOrdered: Bool
    }

    struct HeadingLine {
        let level: Int
        let text: String
    }

    struct BlockQuoteLine {
        let depth: Int
        let text: String
    }

    struct ListItemLine {
        let marker: ListMarker
        let text: String
        let isOrdered: Bool
        let indentLevel: Int

        var columnKey: ListColumnKey {
            ListColumnKey(indentLevel: indentLevel, isOrdered: isOrdered)
        }
    }

    static func displayLines(in markdown: String) -> [String] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else {
            return []
        }

        var lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if normalized.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    static func renderLine(_ line: String) -> RenderLine {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .blank
        }

        if let heading = heading(in: line) {
            return .heading(heading)
        }

        if let quote = blockQuote(in: line) {
            return .blockQuote(quote)
        }

        if let listItem = listItem(in: line) {
            return .listItem(listItem)
        }

        return .paragraph(line)
    }

    static func heading(in line: String) -> HeadingLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else {
            return nil
        }

        let afterHashes = trimmed.dropFirst(level)
        guard afterHashes.isEmpty || afterHashes.first?.isWhitespace == true else {
            return nil
        }

        var text = String(afterHashes).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#"), text.dropLast().last?.isWhitespace == true {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return HeadingLine(level: level, text: text)
    }

    static func blockQuote(in line: String) -> BlockQuoteLine? {
        var rest = line[...]
        var depth = 0

        while true {
            rest = rest.drop(while: { $0 == " " || $0 == "\t" })
            guard rest.first == ">" else {
                break
            }
            depth += 1
            rest = rest.dropFirst()
            if rest.first == " " || rest.first == "\t" {
                rest = rest.dropFirst()
            }
        }

        guard depth > 0 else {
            return nil
        }
        return BlockQuoteLine(depth: depth, text: String(rest))
    }

    static func listItem(in line: String) -> ListItemLine? {
        let leadingWhitespaceCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let indentLevel = leadingWhitespaceCount / 2
        let trimmed = String(line.dropFirst(leadingWhitespaceCount))
        guard !trimmed.isEmpty else {
            return nil
        }

        if let unordered = unorderedListItem(in: trimmed, indentLevel: indentLevel) {
            return unordered
        }
        return orderedListItem(in: trimmed, indentLevel: indentLevel)
    }

    private static func unorderedListItem(
        in line: String,
        indentLevel: Int
    ) -> ListItemLine? {
        guard let marker = line.first,
              marker == "-" || marker == "*" || marker == "+",
              line.dropFirst().first?.isWhitespace == true else {
            return nil
        }

        var text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        var displayMarker = ListMarker.text("-")
        if let checkbox = checkboxMarker(in: text) {
            displayMarker = checkbox.isChecked
                ? .symbol(name: "checkmark.square")
                : .symbol(name: "square")
            text = checkbox.remainingText
        }
        return ListItemLine(
            marker: displayMarker,
            text: text,
            isOrdered: false,
            indentLevel: indentLevel
        )
    }

    private static func orderedListItem(
        in line: String,
        indentLevel: Int
    ) -> ListItemLine? {
        var digitEnd = line.startIndex
        while digitEnd < line.endIndex, line[digitEnd].isNumber {
            digitEnd = line.index(after: digitEnd)
        }
        guard digitEnd > line.startIndex,
              digitEnd < line.endIndex,
              line[digitEnd] == "." || line[digitEnd] == ")" else {
            return nil
        }

        let afterMarker = line.index(after: digitEnd)
        guard afterMarker < line.endIndex, line[afterMarker].isWhitespace else {
            return nil
        }

        let marker = String(line[line.startIndex...digitEnd])
        let text = String(line[afterMarker...]).trimmingCharacters(in: .whitespaces)
        return ListItemLine(
            marker: .text(marker),
            text: text,
            isOrdered: true,
            indentLevel: indentLevel
        )
    }

    private static func checkboxMarker(in text: String) -> (isChecked: Bool, remainingText: String)? {
        let lower = text.lowercased()
        if lower.hasPrefix("[ ]"), isCheckboxBoundary(in: text, markerLength: 3) {
            return (false, checkboxRemainingText(text, markerLength: 3))
        }
        if lower.hasPrefix("[x]"), isCheckboxBoundary(in: text, markerLength: 3) {
            return (true, checkboxRemainingText(text, markerLength: 3))
        }
        return nil
    }

    private static func isCheckboxBoundary(in text: String, markerLength: Int) -> Bool {
        guard let boundary = text.index(text.startIndex, offsetBy: markerLength, limitedBy: text.endIndex),
              boundary < text.endIndex else {
            return true
        }
        return text[boundary].isWhitespace
    }

    private static func checkboxRemainingText(_ text: String, markerLength: Int) -> String {
        var remaining = String(text.dropFirst(markerLength))
        if remaining.first?.isWhitespace == true {
            remaining.removeFirst()
        }
        return remaining
    }
}

final class StreamingMarkdownInlineRenderer {
    private let context: ChatMarkdownRenderingContext

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
    }

    func render(_ text: String, allowPrediction: Bool) -> NSMutableAttributedString {
        render(
            text,
            mode: .body(context: context),
            allowPrediction: allowPrediction
        )
    }

    func render(
        _ text: String,
        font: UIFont,
        foregroundColor: UIColor,
        allowPrediction: Bool
    ) -> NSMutableAttributedString {
        render(
            text,
            mode: .base(font: font, foregroundColor: foregroundColor),
            allowPrediction: allowPrediction
        )
    }

    fileprivate func render(
        _ text: String,
        mode: StreamingMarkdownInlineMode,
        allowPrediction: Bool
    ) -> NSMutableAttributedString {
        StreamingMarkdownInlineScanner(
            source: text,
            mode: mode,
            context: context,
            renderer: self,
            allowPrediction: allowPrediction
        ).render()
    }
}

fileprivate struct StreamingMarkdownInlineMode {
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

    static func body(context: ChatMarkdownRenderingContext) -> StreamingMarkdownInlineMode {
        base(font: context.currentBodyFont(), foregroundColor: context.currentTextColor)
    }

    static func base(font: UIFont, foregroundColor: UIColor) -> StreamingMarkdownInlineMode {
        StreamingMarkdownInlineMode(
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

    func addingSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> StreamingMarkdownInlineMode {
        var copy = self
        copy.symbolicTraits.formUnion(traits)
        copy.font = ChatMarkdownFontTraits.adding(traits, to: font)
        return copy
    }

    func linked(to url: URL?, color: UIColor) -> StreamingMarkdownInlineMode {
        var copy = self
        copy.foregroundColor = color
        copy.linkURL = url
        copy.isUnderlined = true
        return copy
    }

    func underlined() -> StreamingMarkdownInlineMode {
        var copy = self
        copy.isUnderlined = true
        return copy
    }

    func struckThrough() -> StreamingMarkdownInlineMode {
        var copy = self
        copy.isStrikethrough = true
        return copy
    }

    func coded() -> StreamingMarkdownInlineMode {
        var copy = self
        copy.isCode = true
        return copy
    }

    func scaledFont(by scale: CGFloat) -> StreamingMarkdownInlineMode {
        var copy = self
        copy.font = UIFont(descriptor: font.fontDescriptor, size: max(8.0, font.pointSize * scale))
        return copy
    }

    func offsetBaseline(by offset: CGFloat) -> StreamingMarkdownInlineMode {
        var copy = self
        copy.baselineOffset += offset
        return copy
    }

    func marked() -> StreamingMarkdownInlineMode {
        var copy = self
        copy.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.35)
        return copy
    }

    func mathPreview(context: ChatMarkdownRenderingContext) -> StreamingMarkdownInlineMode {
        var copy = self
        copy.font = context.style.codeFont(compatibleWith: context.traitCollection)
        copy.foregroundColor = context.style.secondaryTextColor
        copy.backgroundColor = nil
        copy.isCode = false
        copy.linkURL = nil
        return copy
    }

    func attributes(context: ChatMarkdownRenderingContext) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any]
        if isCode {
            attributes = [
                .font: ChatMarkdownFontTraits.adding(
                    symbolicTraits,
                    to: context.style.codeFont(compatibleWith: context.traitCollection)
                ),
                .foregroundColor: context.style.codeTextColor,
                .chatInlineCodeBackgroundColor: context.style.codeBackgroundColor,
                .chatInlineCodeCornerRadius: ChatMarkdownInlineCodeStyle.cornerRadius
            ]
        } else {
            attributes = [
                .font: font,
                .foregroundColor: foregroundColor
            ]
        }

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
        return attributes
    }
}

private final class StreamingMarkdownInlineScanner {
    private struct StackEntry {
        let tagName: String
        let mode: StreamingMarkdownInlineMode
    }

    private let source: String
    private let context: ChatMarkdownRenderingContext
    private let renderer: StreamingMarkdownInlineRenderer
    private let allowPrediction: Bool
    private var mode: StreamingMarkdownInlineMode
    private var index: String.Index
    private var htmlStack: [StackEntry] = []

    init(
        source: String,
        mode: StreamingMarkdownInlineMode,
        context: ChatMarkdownRenderingContext,
        renderer: StreamingMarkdownInlineRenderer,
        allowPrediction: Bool
    ) {
        self.source = source
        self.mode = mode
        self.context = context
        self.renderer = renderer
        self.allowPrediction = allowPrediction
        index = source.startIndex
    }

    func render() -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        while index < source.endIndex {
            if consumeMathParen(into: result) { continue }
            if consumeEscape(into: result) { continue }
            if consumeInlineCode(into: result) { continue }
            if consumeMathDollar(into: result) { continue }
            if consumeImage(into: result) { continue }
            if consumeLink(into: result) { continue }
            if consumeHTML(into: result) { continue }
            if consumeEmphasis(into: result) { continue }
            append(String(source[index]), to: result)
            index = source.index(after: index)
        }

        return result
    }

    private func consumeEscape(into result: NSMutableAttributedString) -> Bool {
        guard source[index] == "\\",
              let next = source.index(index, offsetBy: 1, limitedBy: source.endIndex),
              next < source.endIndex else {
            return false
        }
        append(String(source[next]), to: result)
        index = source.index(after: next)
        return true
    }

    private func consumeInlineCode(into result: NSMutableAttributedString) -> Bool {
        guard source[index] == "`" else {
            return false
        }

        let run = countRepeated("`", from: index)
        let openerEnd = source.index(index, offsetBy: run)
        if let close = findToken(String(repeating: "`", count: run), from: openerEnd) {
            let code = String(source[openerEnd..<close])
            let codeEnd = source.index(close, offsetBy: run)
            appendInlineCode(
                code,
                to: result,
                nextCharacter: codeEnd < source.endIndex ? source[codeEnd] : nil
            )
            index = codeEnd
            return true
        }

        guard allowPrediction else {
            append(String(source[index..<openerEnd]), to: result)
            index = openerEnd
            return true
        }

        appendInlineCode(String(source[openerEnd..<source.endIndex]), to: result, nextCharacter: nil)
        index = source.endIndex
        return true
    }

    private func consumeMathDollar(into result: NSMutableAttributedString) -> Bool {
        guard source[index] == "$",
              !hasPrefix("$$", at: index),
              isInlineMathDollar(at: index) else {
            return false
        }

        let contentStart = source.index(after: index)
        if let close = findUnescapedDollar(from: contentStart) {
            appendInlineMath(
                latex: String(source[contentStart..<close]),
                rawFallback: String(source[index...close]),
                to: result
            )
            index = source.index(after: close)
            return true
        }

        guard allowPrediction else {
            append("$", to: result)
            index = source.index(after: index)
            return true
        }

        appendMathPreview(String(source[index..<source.endIndex]), to: result)
        index = source.endIndex
        return true
    }

    private func consumeMathParen(into result: NSMutableAttributedString) -> Bool {
        guard hasPrefix("\\(", at: index) else {
            return false
        }

        let contentStart = source.index(index, offsetBy: 2)
        if let close = findToken("\\)", from: contentStart) {
            appendInlineMath(
                latex: String(source[contentStart..<close]),
                rawFallback: String(source[index..<source.index(close, offsetBy: 2)]),
                to: result
            )
            index = source.index(close, offsetBy: 2)
            return true
        }

        guard allowPrediction else {
            append("\\", to: result)
            index = source.index(after: index)
            return true
        }

        appendMathPreview(String(source[index..<source.endIndex]), to: result)
        index = source.endIndex
        return true
    }

    private func consumeImage(into result: NSMutableAttributedString) -> Bool {
        guard hasPrefix("![", at: index) else {
            return false
        }
        guard let link = parseBracketLink(isImage: true) else {
            if allowPrediction {
                append(String(source[index..<source.endIndex]), to: result)
                index = source.endIndex
                return true
            }
            return false
        }

        result.append(
            NSAttributedString(
                string: context.imageDisplayText(source: link.destination, altText: link.label),
                attributes: context.secondaryAttributes()
            )
        )
        index = link.end
        return true
    }

    private func consumeLink(into result: NSMutableAttributedString) -> Bool {
        guard source[index] == "[" else {
            return false
        }
        guard let link = parseBracketLink(isImage: false) else {
            if allowPrediction {
                append(String(source[index..<source.endIndex]), to: result)
                index = source.endIndex
                return true
            }
            return false
        }

        let url = URL(string: link.destination)
        result.append(
            renderer.render(
                link.label,
                mode: mode.linked(to: url, color: context.style.linkColor),
                allowPrediction: allowPrediction
            )
        )
        index = link.end
        return true
    }

    private func consumeHTML(into result: NSMutableAttributedString) -> Bool {
        guard source[index] == "<",
              let tagEnd = findTagEnd(from: index) else {
            return false
        }

        let raw = String(source[index...tagEnd])
        guard let tag = ChatMarkdownHTMLSupport.parseTag(raw) else {
            return false
        }

        result.append(render(tag))
        index = source.index(after: tagEnd)
        return true
    }

    private func consumeEmphasis(into result: NSMutableAttributedString) -> Bool {
        if consumeDelimited("~~", transform: { $0.struckThrough() }, into: result) {
            return true
        }
        if consumeDelimited("**", transform: { $0.addingSymbolicTraits(.traitBold) }, into: result) {
            return true
        }
        if consumeDelimited("__", transform: { $0.addingSymbolicTraits(.traitBold) }, into: result) {
            return true
        }
        if consumeDelimited("*", transform: { $0.addingSymbolicTraits(.traitItalic) }, into: result) {
            return true
        }
        if consumeDelimited("_", transform: { $0.addingSymbolicTraits(.traitItalic) }, into: result) {
            return true
        }
        return false
    }

    private func consumeDelimited(
        _ token: String,
        transform: (StreamingMarkdownInlineMode) -> StreamingMarkdownInlineMode,
        into result: NSMutableAttributedString
    ) -> Bool {
        guard hasPrefix(token, at: index),
              isUsableDelimiter(token) else {
            return false
        }

        let contentStart = source.index(index, offsetBy: token.count)
        if let close = findToken(token, from: contentStart) {
            let text = String(source[contentStart..<close])
            result.append(
                renderer.render(
                    text,
                    mode: transform(mode),
                    allowPrediction: allowPrediction
                )
            )
            index = source.index(close, offsetBy: token.count)
            return true
        }

        guard allowPrediction else {
            return false
        }

        result.append(
            renderer.render(
                String(source[contentStart..<source.endIndex]),
                mode: transform(mode),
                allowPrediction: allowPrediction
            )
        )
        index = source.endIndex
        return true
    }

    private func render(_ tag: ChatMarkdownHTMLTag) -> NSAttributedString {
        if ChatMarkdownHTMLSupport.disallowedRawHTMLTagNames.contains(tag.name) {
            return NSAttributedString(string: tag.rawHTML, attributes: context.secondaryAttributes())
        }

        if tag.isClosing {
            if tag.name == "q" {
                restoreMode(closing: tag.name)
                return NSAttributedString(string: "\"", attributes: mode.attributes(context: context))
            }
            restoreMode(closing: tag.name)
            return NSAttributedString()
        }

        switch tag.name {
        case "br":
            return NSAttributedString(string: "\n", attributes: mode.attributes(context: context))
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
            let quote = NSAttributedString(string: "\"", attributes: mode.attributes(context: context))
            if !tag.isSelfClosing {
                pushMode(for: tag)
            }
            return quote
        case "source", "track", "param", "meta", "link", "base", "col", "wbr":
            return NSAttributedString()
        default:
            break
        }

        if !tag.isSelfClosing {
            pushMode(for: tag)
        }
        return NSAttributedString()
    }

    private func pushMode(for tag: ChatMarkdownHTMLTag) {
        let previousMode = mode
        mode = transformedMode(opening: tag)
        htmlStack.append(StackEntry(tagName: tag.name, mode: previousMode))
    }

    private func restoreMode(closing tagName: String) {
        guard let stackIndex = htmlStack.lastIndex(where: { $0.tagName == tagName }) else {
            return
        }
        mode = htmlStack[stackIndex].mode
        htmlStack.removeSubrange(stackIndex...)
    }

    private func transformedMode(opening tag: ChatMarkdownHTMLTag) -> StreamingMarkdownInlineMode {
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
            return mode.linked(to: url, color: context.style.linkColor)
        case "abbr":
            return mode.underlined()
        default:
            return mode
        }
    }

    private func appendInlineMath(
        latex: String,
        rawFallback: String,
        to result: NSMutableAttributedString
    ) {
        if let renderedImage = ChatMarkdownMathImageRenderer.renderInline(
            latex: latex,
            font: mode.font,
            textColor: mode.foregroundColor,
            traitCollection: context.traitCollection
        ) {
            result.append(NSAttributedString(attachment: ChatMarkdownMathTextAttachment(renderedImage: renderedImage)))
        } else {
            append(rawFallback, to: result)
        }
    }

    private func appendMathPreview(_ text: String, to result: NSMutableAttributedString) {
        result.append(
            NSAttributedString(
                string: text,
                attributes: mode.mathPreview(context: context).attributes(context: context)
            )
        )
    }

    private func appendInlineCode(
        _ code: String,
        to result: NSMutableAttributedString,
        nextCharacter: Character?
    ) {
        let regularAttributes = mode.attributes(context: context)
        if let previous = result.string.last, !isMarginBoundary(previous) {
            result.append(
                NSAttributedString(
                    string: ChatMarkdownInlineCodeStyle.outerMargin,
                    attributes: regularAttributes
                )
            )
        }

        result.append(
            NSAttributedString(
                string: code,
                attributes: mode.coded().attributes(context: context)
            )
        )

        if let nextCharacter, !isMarginBoundary(nextCharacter) {
            result.append(
                NSAttributedString(
                    string: ChatMarkdownInlineCodeStyle.outerMargin,
                    attributes: regularAttributes
                )
            )
        }
    }

    private func checkboxAttachment(isChecked: Bool) -> NSAttributedString {
        let name = isChecked ? "checkmark.square" : "square"
        let configuration = UIImage.SymbolConfiguration(font: mode.font, scale: .medium)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(
                mode.foregroundColor.resolvedColor(with: context.traitCollection),
                renderingMode: .alwaysOriginal
            ) else {
            return NSAttributedString(
                string: isChecked ? "☑" : "☐",
                attributes: mode.attributes(context: context)
            )
        }

        let symbol = NSMutableAttributedString(attachment: NSTextAttachment(image: image))
        symbol.addAttributes(mode.attributes(context: context), range: NSRange(location: 0, length: symbol.length))
        return symbol
    }

    private func isMarginBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private func append(_ text: String, to result: NSMutableAttributedString) {
        guard !text.isEmpty else {
            return
        }
        result.append(NSAttributedString(string: text, attributes: mode.attributes(context: context)))
    }
}

private extension StreamingMarkdownInlineScanner {
    struct BracketLink {
        let label: String
        let destination: String
        let end: String.Index
    }

    func parseBracketLink(isImage: Bool) -> BracketLink? {
        let labelStart = source.index(index, offsetBy: isImage ? 2 : 1)
        guard let labelEnd = findUnescaped("]", from: labelStart) else {
            return nil
        }
        let openParen = source.index(after: labelEnd)
        guard openParen < source.endIndex, source[openParen] == "(" else {
            return nil
        }
        let destinationStart = source.index(after: openParen)
        guard let closeParen = findLinkDestinationEnd(from: destinationStart) else {
            return nil
        }

        let rawDestination = String(source[destinationStart..<closeParen])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = rawDestination
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? rawDestination
        return BracketLink(
            label: String(source[labelStart..<labelEnd]),
            destination: destination,
            end: source.index(after: closeParen)
        )
    }

    func findLinkDestinationEnd(from start: String.Index) -> String.Index? {
        var cursor = start
        var depth = 0
        while cursor < source.endIndex {
            if source[cursor] == "\\" {
                cursor = source.index(after: cursor)
                if cursor < source.endIndex {
                    cursor = source.index(after: cursor)
                }
                continue
            }
            if source[cursor] == "(" {
                depth += 1
            } else if source[cursor] == ")" {
                if depth == 0 {
                    return cursor
                }
                depth -= 1
            } else if source[cursor].isNewline {
                return nil
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    func findUnescaped(_ character: Character, from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "\\" {
                cursor = source.index(after: cursor)
                if cursor < source.endIndex {
                    cursor = source.index(after: cursor)
                }
                continue
            }
            if source[cursor] == character {
                return cursor
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    func findUnescapedDollar(from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "\\" {
                cursor = source.index(after: cursor)
                if cursor < source.endIndex {
                    cursor = source.index(after: cursor)
                }
                continue
            }
            if source[cursor] == "$" {
                return cursor
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    func findToken(_ token: String, from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if hasPrefix(token, at: cursor) {
                return cursor
            }
            if source[cursor] == "\\" {
                cursor = source.index(after: cursor)
                if cursor < source.endIndex {
                    cursor = source.index(after: cursor)
                }
                continue
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    func findTagEnd(from start: String.Index) -> String.Index? {
        var cursor = source.index(after: start)
        var quote: Character?
        while cursor < source.endIndex {
            let character = source[cursor]
            if let currentQuote = quote {
                if character == currentQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return cursor
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    func hasPrefix(_ token: String, at position: String.Index) -> Bool {
        guard let end = source.index(position, offsetBy: token.count, limitedBy: source.endIndex) else {
            return false
        }
        return String(source[position..<end]) == token
    }

    func countRepeated(_ character: Character, from start: String.Index) -> Int {
        var cursor = start
        var count = 0
        while cursor < source.endIndex, source[cursor] == character {
            count += 1
            cursor = source.index(after: cursor)
        }
        return count
    }

    func isInlineMathDollar(at position: String.Index) -> Bool {
        let next = source.index(after: position)
        guard next < source.endIndex, !source[next].isWhitespace else {
            return false
        }
        if position > source.startIndex {
            let previous = source.index(before: position)
            if source[previous].isNumber {
                return false
            }
        }
        return true
    }

    func isUsableDelimiter(_ token: String) -> Bool {
        if token == "_" || token == "__" {
            let before = index > source.startIndex ? source[source.index(before: index)] : nil
            let afterIndex = source.index(index, offsetBy: token.count)
            let after = afterIndex < source.endIndex ? source[afterIndex] : nil
            if before?.isLetterOrNumber == true && after?.isLetterOrNumber == true {
                return false
            }
        }
        return true
    }
}

private extension Character {
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
