//
//  ChatMarkdownMathSupport.swift
//  UniLLMs
//
//  Lightweight LaTeX math detection and drawing for chat Markdown.
//  Created by OpenAI on 2026/5/14.
//

import CoreText
import UIKit

struct ChatMarkdownMathBlock: Equatable {
    let latex: String
}

struct ChatMarkdownMathInlineSpan {
    let latex: String
    let range: Range<String.Index>
}

enum ChatMarkdownMathDelimiterScanner {
    static func standaloneDisplayMath(in text: String) -> ChatMarkdownMathBlock? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 {
            let content = trimmed
                .dropFirst(2)
                .dropLast(2)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : ChatMarkdownMathBlock(latex: content)
        }

        if trimmed.hasPrefix("\\["), trimmed.hasSuffix("\\]"), trimmed.count >= 4 {
            let content = trimmed
                .dropFirst(2)
                .dropLast(2)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : ChatMarkdownMathBlock(latex: content)
        }

        return nil
    }

    static func inlineSpans(in text: String) -> [ChatMarkdownMathInlineSpan] {
        var spans: [ChatMarkdownMathInlineSpan] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "\\",
               let nextIndex = text.index(index, offsetBy: 1, limitedBy: text.endIndex),
               nextIndex < text.endIndex,
               text[nextIndex] == "(",
               let closingRange = text.range(of: "\\)", range: text.index(after: nextIndex)..<text.endIndex) {
                let contentRange = text.index(after: nextIndex)..<closingRange.lowerBound
                let latex = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !latex.isEmpty {
                    spans.append(
                        ChatMarkdownMathInlineSpan(
                            latex: latex,
                            range: index..<closingRange.upperBound
                        )
                    )
                }
                index = closingRange.upperBound
                continue
            }

            if text[index] == "$",
               isSingleDollar(at: index, in: text),
               isDollarOpening(at: index, in: text),
               let closingIndex = closingDollar(after: index, in: text) {
                let contentRange = text.index(after: index)..<closingIndex
                let latex = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !latex.isEmpty {
                    spans.append(
                        ChatMarkdownMathInlineSpan(
                            latex: latex,
                            range: index..<text.index(after: closingIndex)
                        )
                    )
                }
                index = text.index(after: closingIndex)
                continue
            }

            index = text.index(after: index)
        }

        return spans
    }

    private static func closingDollar(after openingIndex: String.Index, in text: String) -> String.Index? {
        var index = text.index(after: openingIndex)
        while index < text.endIndex {
            if text[index] == "$",
               isSingleDollar(at: index, in: text),
               !isEscaped(index, in: text),
               isDollarClosing(at: index, in: text) {
                return index
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func isSingleDollar(at index: String.Index, in text: String) -> Bool {
        let previousIsDollar = index > text.startIndex && text[text.index(before: index)] == "$"
        let nextIndex = text.index(after: index)
        let nextIsDollar = nextIndex < text.endIndex && text[nextIndex] == "$"
        return !previousIsDollar && !nextIsDollar
    }

    private static func isDollarOpening(at index: String.Index, in text: String) -> Bool {
        guard !isEscaped(index, in: text) else {
            return false
        }

        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex else {
            return false
        }

        return !text[nextIndex].isWhitespace && !text[nextIndex].isNumber
    }

    private static func isDollarClosing(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return false
        }

        let previousIndex = text.index(before: index)
        return !text[previousIndex].isWhitespace
    }

    private static func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var slashCount = 0
        var current = index
        while current > text.startIndex {
            let previous = text.index(before: current)
            guard text[previous] == "\\" else {
                break
            }
            slashCount += 1
            current = previous
        }

        return slashCount % 2 == 1
    }
}

enum ChatMarkdownMathMarkdownSegment {
    case markdown(String)
    case displayMath(ChatMarkdownMathBlock)
}

enum ChatMarkdownMathBlockSplitter {
    static func segments(in markdown: String) -> [ChatMarkdownMathMarkdownSegment] {
        let lines = markdownLineSlices(in: markdown)
        guard !lines.isEmpty else {
            return []
        }

        var segments: [ChatMarkdownMathMarkdownSegment] = []
        var markdownBuffer = ""
        var index = 0
        var openFence: (marker: Character, count: Int)?

        func flushMarkdownBuffer() {
            guard !markdownBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                markdownBuffer = ""
                return
            }
            segments.append(.markdown(markdownBuffer))
            markdownBuffer = ""
        }

        while index < lines.count {
            let line = lines[index]
            let lineText = line.withoutTrailingNewline

            if let fence = openFence {
                markdownBuffer += line.raw
                if let closingFence = fenceInfo(in: lineText),
                   closingFence.marker == fence.marker,
                   closingFence.count >= fence.count {
                    openFence = nil
                }
                index += 1
                continue
            }

            if let fence = fenceInfo(in: lineText) {
                openFence = fence
                markdownBuffer += line.raw
                index += 1
                continue
            }

            if let displayMath = displayMathStarting(at: index, in: lines) {
                flushMarkdownBuffer()
                segments.append(.displayMath(displayMath.block))
                index = displayMath.nextIndex
                continue
            }

            markdownBuffer += line.raw
            index += 1
        }

        flushMarkdownBuffer()
        return segments
    }

    private static func displayMathStarting(
        at index: Int,
        in lines: [MarkdownLineSlice]
    ) -> (block: ChatMarkdownMathBlock, nextIndex: Int)? {
        guard index < lines.count,
              isDisplayMathOpeningLine(lines[index].withoutTrailingNewline) else {
            return nil
        }

        var collected = lines[index].raw
        if let block = ChatMarkdownMathDelimiterScanner.standaloneDisplayMath(
            in: lines[index].withoutTrailingNewline
        ) {
            return (block, index + 1)
        }

        let closingDelimiter = displayMathClosingDelimiter(forOpeningLine: lines[index].withoutTrailingNewline)
        var currentIndex = index + 1
        while currentIndex < lines.count {
            collected += lines[currentIndex].raw
            let trimmedLine = lines[currentIndex]
                .withoutTrailingNewline
                .trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasSuffix(closingDelimiter),
               let block = ChatMarkdownMathDelimiterScanner.standaloneDisplayMath(in: collected) {
                return (block, currentIndex + 1)
            }
            currentIndex += 1
        }

        return nil
    }

    private static func isDisplayMathOpeningLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "$$" ||
            trimmed == "\\[" ||
            (trimmed.hasPrefix("$$") && trimmed.count > 2) ||
            (trimmed.hasPrefix("\\[") && trimmed.count > 2)
    }

    private static func displayMathClosingDelimiter(forOpeningLine line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("\\[") ? "\\]" : "$$"
    }

    private static func fenceInfo(in line: String) -> (marker: Character, count: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first,
              marker == "`" || marker == "~" else {
            return nil
        }

        let count = trimmed.prefix { $0 == marker }.count
        return count >= 3 ? (marker, count) : nil
    }

    private static func markdownLineSlices(in markdown: String) -> [MarkdownLineSlice] {
        guard !markdown.isEmpty else {
            return []
        }

        var lines: [MarkdownLineSlice] = []
        var startIndex = markdown.startIndex
        while startIndex < markdown.endIndex {
            if let newlineRange = markdown[startIndex...].range(of: "\n") {
                let raw = String(markdown[startIndex..<newlineRange.upperBound])
                let withoutNewline = String(markdown[startIndex..<newlineRange.lowerBound])
                lines.append(MarkdownLineSlice(raw: raw, withoutTrailingNewline: withoutNewline))
                startIndex = newlineRange.upperBound
            } else {
                let raw = String(markdown[startIndex...])
                lines.append(MarkdownLineSlice(raw: raw, withoutTrailingNewline: raw))
                startIndex = markdown.endIndex
            }
        }
        return lines
    }

    private struct MarkdownLineSlice {
        let raw: String
        let withoutTrailingNewline: String
    }
}

struct ChatMarkdownMathRenderedImage {
    let image: UIImage
    let baseline: CGFloat
}

enum ChatMarkdownMathImageRenderer {
    static func renderInline(
        latex: String,
        font: UIFont,
        textColor: UIColor,
        traitCollection: UITraitCollection
    ) -> ChatMarkdownMathRenderedImage? {
        render(
            latex: latex,
            fontSize: max(8.0, font.pointSize * 0.96),
            textColor: textColor,
            horizontalPadding: 1.0,
            verticalPadding: 1.0,
            traitCollection: traitCollection,
            displayStyle: false
        )
    }

    static func renderDisplay(
        latex: String,
        font: UIFont,
        textColor: UIColor,
        traitCollection: UITraitCollection
    ) -> ChatMarkdownMathRenderedImage? {
        render(
            latex: latex,
            fontSize: max(10.0, font.pointSize * 1.12),
            textColor: textColor,
            horizontalPadding: 12.0,
            verticalPadding: 8.0,
            traitCollection: traitCollection,
            displayStyle: true
        )
    }

    private static func render(
        latex: String,
        fontSize: CGFloat,
        textColor: UIColor,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        traitCollection: UITraitCollection,
        displayStyle: Bool
    ) -> ChatMarkdownMathRenderedImage? {
        ChatMarkdownKaTeXFontLoader.ensureFontsRegistered()

        let resolvedColor = textColor.resolvedColor(with: traitCollection)
        let parser = ChatMarkdownLatexParser(
            latex: latex,
            fontSize: fontSize,
            textColor: resolvedColor,
            displayStyle: displayStyle
        )
        let root = parser.parse()
        guard root.size.width > 0.0, root.size.height > 0.0 else {
            return nil
        }

        let scale = max(1.0, traitCollection.displayScale)
        let size = CGSize(
            width: ceil(root.size.width + horizontalPadding * 2.0),
            height: ceil(root.size.height + verticalPadding * 2.0)
        )
        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        format.scale = scale
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            root.draw(
                in: rendererContext.cgContext,
                at: CGPoint(x: horizontalPadding, y: verticalPadding)
            )
        }

        return ChatMarkdownMathRenderedImage(
            image: image,
            baseline: verticalPadding + root.baseline
        )
    }
}

final class ChatMarkdownMathTextAttachment: NSTextAttachment {
    private let renderedImage: ChatMarkdownMathRenderedImage

    init(renderedImage: ChatMarkdownMathRenderedImage) {
        self.renderedImage = renderedImage
        super.init(data: nil, ofType: nil)
        image = renderedImage.image
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let height = renderedImage.image.size.height
        let descent = height - renderedImage.baseline
        return CGRect(
            x: 0.0,
            y: -descent,
            width: renderedImage.image.size.width,
            height: height
        )
    }
}

private final class ChatMarkdownKaTeXFontLoader: NSObject {
    private static let shared = ChatMarkdownKaTeXFontLoader()

    private let lock = NSLock()
    private var didRegister = false
    private let fontNames = [
        "KaTeX_AMS-Regular",
        "KaTeX_Caligraphic-Bold",
        "KaTeX_Caligraphic-Regular",
        "KaTeX_Fraktur-Bold",
        "KaTeX_Fraktur-Regular",
        "KaTeX_Main-Bold",
        "KaTeX_Main-BoldItalic",
        "KaTeX_Main-Italic",
        "KaTeX_Main-Regular",
        "KaTeX_Math-BoldItalic",
        "KaTeX_Math-Italic",
        "KaTeX_SansSerif-Bold",
        "KaTeX_SansSerif-Italic",
        "KaTeX_SansSerif-Regular",
        "KaTeX_Script-Regular",
        "KaTeX_Size1-Regular",
        "KaTeX_Size2-Regular",
        "KaTeX_Size3-Regular",
        "KaTeX_Size4-Regular",
        "KaTeX_Typewriter-Regular"
    ]

    static func ensureFontsRegistered() {
        shared.registerFontsIfNeeded()
    }

    private func registerFontsIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard !didRegister else {
            return
        }

        for fontName in fontNames {
            for fontURL in fontURLs(for: fontName) {
                registerFont(at: fontURL)
            }
        }
        didRegister = true
    }

    private func fontURLs(for fontName: String) -> [URL] {
        let bundles = [Bundle.main, Bundle(for: Self.self)]
        var urls: [URL] = []
        for bundle in bundles {
            if let url = bundle.url(forResource: fontName, withExtension: "ttf", subdirectory: "KaTeXFonts") {
                urls.append(url)
            }
            if let url = bundle.url(forResource: fontName, withExtension: "ttf", subdirectory: "Resources/KaTeXFonts") {
                urls.append(url)
            }
            if let url = bundle.url(forResource: fontName, withExtension: "ttf") {
                urls.append(url)
            }
        }
        return urls
    }

    private func registerFont(at fontURL: URL) {
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        if !success {
            _ = error?.takeRetainedValue()
        }
    }
}

private enum ChatMarkdownLatexToken: Equatable {
    case command(String)
    case text(String)
    case lBrace
    case rBrace
    case hat
    case underscore
    case ampersand
    case newLine
}

private struct ChatMarkdownLatexLexer {
    private let characters: [Character]
    private var index = 0

    init(_ latex: String) {
        characters = Array(latex)
    }

    mutating func tokenize() -> [ChatMarkdownLatexToken] {
        var tokens: [ChatMarkdownLatexToken] = []
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\":
                tokens.append(readCommand())
            case "{":
                tokens.append(.lBrace)
                index += 1
            case "}":
                tokens.append(.rBrace)
                index += 1
            case "^":
                tokens.append(.hat)
                index += 1
            case "_":
                tokens.append(.underscore)
                index += 1
            case "&":
                tokens.append(.ampersand)
                index += 1
            case "\n":
                tokens.append(.text(" "))
                index += 1
            case "~":
                tokens.append(.text(" "))
                index += 1
            default:
                tokens.append(.text(String(character)))
                index += 1
            }
        }
        return tokens
    }

    private mutating func readCommand() -> ChatMarkdownLatexToken {
        index += 1
        guard index < characters.count else {
            return .text("\\")
        }

        if characters[index] == "\\" {
            index += 1
            return .newLine
        }

        if !characters[index].isLetter {
            let command = String(characters[index])
            index += 1
            return .command(command)
        }

        var command = ""
        while index < characters.count, characters[index].isLetter {
            command.append(characters[index])
            index += 1
        }
        return .command(command)
    }
}

private final class ChatMarkdownLatexParser {
    private let tokens: [ChatMarkdownLatexToken]
    private let textColor: UIColor
    private let displayStyle: Bool
    private var index = 0

    init(
        latex: String,
        fontSize: CGFloat,
        textColor: UIColor,
        displayStyle: Bool
    ) {
        var lexer = ChatMarkdownLatexLexer(latex)
        tokens = lexer.tokenize()
        self.textColor = textColor
        self.displayStyle = displayStyle
        rootFont = ChatMarkdownLatexFont.main(size: fontSize)
    }

    private let rootFont: UIFont

    func parse() -> ChatMarkdownMathNode {
        parseExpression(font: rootFont) { _ in false }
    }

    private func parseExpression(
        font: UIFont,
        until shouldStop: (ChatMarkdownLatexToken) -> Bool
    ) -> ChatMarkdownMathNode {
        var nodes: [ChatMarkdownMathNode] = []

        while index < tokens.count {
            let token = tokens[index]
            if shouldStop(token) || token == .rBrace {
                break
            }

            guard let node = parseAtomWithScripts(font: font) else {
                index += 1
                continue
            }
            nodes.append(node)
        }

        if nodes.isEmpty {
            return ChatMarkdownMathTextNode(text: "", font: font, color: textColor)
        }
        if nodes.count == 1 {
            return nodes[0]
        }
        return ChatMarkdownMathHorizontalNode(children: nodes)
    }

    private func parseAtomWithScripts(font: UIFont) -> ChatMarkdownMathNode? {
        guard let atom = parseAtom(font: font) else {
            return nil
        }

        var upper: ChatMarkdownMathNode?
        var lower: ChatMarkdownMathNode?
        let scriptFont = font.withSize(max(6.0, font.pointSize * 0.62))

        while index < tokens.count {
            switch tokens[index] {
            case .hat:
                index += 1
                upper = parseNextItem(font: scriptFont)
            case .underscore:
                index += 1
                lower = parseNextItem(font: scriptFont)
            default:
                if upper != nil || lower != nil {
                    if displayStyle, atom.prefersVerticalLimits {
                        return ChatMarkdownMathLimitsNode(base: atom.node, upper: upper, lower: lower)
                    }
                    return ChatMarkdownMathScriptsNode(base: atom.node, upper: upper, lower: lower)
                }
                return atom.node
            }
        }

        if upper != nil || lower != nil {
            if displayStyle, atom.prefersVerticalLimits {
                return ChatMarkdownMathLimitsNode(base: atom.node, upper: upper, lower: lower)
            }
            return ChatMarkdownMathScriptsNode(base: atom.node, upper: upper, lower: lower)
        }

        return atom.node
    }

    private func parseAtom(font: UIFont) -> (node: ChatMarkdownMathNode, prefersVerticalLimits: Bool)? {
        guard index < tokens.count else {
            return nil
        }

        let token = tokens[index]
        switch token {
        case let .text(text):
            index += 1
            let nodeFont = ChatMarkdownLatexFont.font(forLiteral: text, size: font.pointSize)
            return (ChatMarkdownMathTextNode(text: text, font: nodeFont, color: textColor), false)
        case .lBrace:
            index += 1
            let node = parseExpression(font: font) { $0 == .rBrace }
            consume(.rBrace)
            return (node, false)
        case let .command(command):
            index += 1
            return parseCommand(command, font: font)
        case .newLine:
            index += 1
            return (ChatMarkdownMathSpaceNode(width: font.pointSize * 0.8), false)
        case .ampersand, .rBrace:
            return nil
        case .hat, .underscore:
            index += 1
            return (ChatMarkdownMathTextNode(text: token.rawText, font: font, color: textColor), false)
        }
    }

    private func parseCommand(
        _ command: String,
        font: UIFont
    ) -> (node: ChatMarkdownMathNode, prefersVerticalLimits: Bool)? {
        switch command {
        case "frac":
            let numerator = parseNextItem(font: font.withSize(font.pointSize * 0.9))
            let denominator = parseNextItem(font: font.withSize(font.pointSize * 0.9))
            return (
                ChatMarkdownMathFractionNode(
                    numerator: numerator,
                    denominator: denominator,
                    color: textColor
                ),
                false
            )
        case "sqrt":
            let inner = parseNextItem(font: font)
            return (ChatMarkdownMathSqrtNode(inner: inner, color: textColor), false)
        case "binom":
            let numerator = parseNextItem(font: font.withSize(font.pointSize * 0.9))
            let denominator = parseNextItem(font: font.withSize(font.pointSize * 0.9))
            return (ChatMarkdownMathBinomNode(numerator: numerator, denominator: denominator, color: textColor), false)
        case "overline":
            return (
                ChatMarkdownMathEnclosureNode(
                    child: parseNextItem(font: font),
                    kind: .overline,
                    color: textColor
                ),
                false
            )
        case "underline":
            return (
                ChatMarkdownMathEnclosureNode(
                    child: parseNextItem(font: font),
                    kind: .underline,
                    color: textColor
                ),
                false
            )
        case "boxed":
            return (
                ChatMarkdownMathEnclosureNode(
                    child: parseNextItem(font: font),
                    kind: .boxed,
                    color: textColor
                ),
                false
            )
        case "left":
            return (parseLeftRight(font: font), false)
        case "begin":
            return (parseMatrix(font: font), false)
        case "text", "mathrm":
            return (parseNextItem(font: ChatMarkdownLatexFont.main(size: font.pointSize)), false)
        case "mathbf", "textbf":
            return (parseNextItem(font: ChatMarkdownLatexFont.mainBold(size: font.pointSize)), false)
        case "mathit":
            return (parseNextItem(font: ChatMarkdownLatexFont.mainItalic(size: font.pointSize)), false)
        case "mathbb":
            return (parseNextItem(font: ChatMarkdownLatexFont.ams(size: font.pointSize)), false)
        case "mathcal":
            return (parseNextItem(font: ChatMarkdownLatexFont.caligraphic(size: font.pointSize)), false)
        case "quad":
            return (ChatMarkdownMathSpaceNode(width: font.pointSize), false)
        case "qquad":
            return (ChatMarkdownMathSpaceNode(width: font.pointSize * 2.0), false)
        case ",", " ":
            return (ChatMarkdownMathSpaceNode(width: font.pointSize * 0.25), false)
        case "!":
            return (ChatMarkdownMathSpaceNode(width: -font.pointSize * 0.12), false)
        default:
            if ChatMarkdownLatexSymbols.verticalLimits.contains(command) {
                let symbol = ChatMarkdownLatexSymbols.map[command] ?? command
                let node = ChatMarkdownMathTextNode(
                    text: symbol,
                    font: ChatMarkdownLatexFont.main(size: font.pointSize * 1.35),
                    color: textColor
                )
                return (node, true)
            }

            if ChatMarkdownLatexSymbols.functions.contains(command) {
                return (
                    ChatMarkdownMathTextNode(
                        text: command,
                        font: ChatMarkdownLatexFont.main(size: font.pointSize),
                        color: textColor
                    ),
                    false
                )
            }

            if let symbol = ChatMarkdownLatexSymbols.map[command] {
                return (
                    ChatMarkdownMathTextNode(
                        text: symbol,
                        font: ChatMarkdownLatexFont.main(size: font.pointSize),
                        color: textColor
                    ),
                    false
                )
            }

            return (
                ChatMarkdownMathTextNode(
                    text: command,
                    font: ChatMarkdownLatexFont.main(size: font.pointSize),
                    color: textColor
                ),
                false
            )
        }
    }

    private func parseNextItem(font: UIFont) -> ChatMarkdownMathNode {
        guard index < tokens.count else {
            return ChatMarkdownMathTextNode(text: "", font: font, color: textColor)
        }

        if tokens[index] == .lBrace {
            index += 1
            let node = parseExpression(font: font) { $0 == .rBrace }
            consume(.rBrace)
            return node
        }

        return parseAtomWithScripts(font: font)
            ?? ChatMarkdownMathTextNode(text: "", font: font, color: textColor)
    }

    private func parseLeftRight(font: UIFont) -> ChatMarkdownMathNode {
        let leftDelimiter = consumeDelimiterText()
        let inner = parseExpression(font: font) { token in
            token == .command("right")
        }
        if index < tokens.count, tokens[index] == .command("right") {
            index += 1
        }
        let rightDelimiter = consumeDelimiterText()
        let delimiterSize = max(font.pointSize, inner.size.height * 0.95)
        let leftNode = ChatMarkdownMathTextNode(
            text: displayDelimiter(leftDelimiter),
            font: ChatMarkdownLatexFont.main(size: delimiterSize),
            color: textColor
        )
        let rightNode = ChatMarkdownMathTextNode(
            text: displayDelimiter(rightDelimiter),
            font: ChatMarkdownLatexFont.main(size: delimiterSize),
            color: textColor
        )
        return ChatMarkdownMathHorizontalNode(children: [leftNode, inner, rightNode])
    }

    private func parseMatrix(font: UIFont) -> ChatMarkdownMathNode {
        let environment = parseRequiredGroupText()
        let matrixKind = ChatMarkdownMathMatrixNode.Kind(environment: environment)
        var rows: [[ChatMarkdownMathNode]] = []
        var currentRow: [ChatMarkdownMathNode] = []

        while index < tokens.count {
            if tokens[index] == .command("end") {
                index += 1
                _ = parseRequiredGroupText()
                break
            }

            let cell = parseExpression(font: font.withSize(font.pointSize * 0.92)) { token in
                token == .ampersand || token == .newLine || token == .command("end")
            }
            currentRow.append(cell)

            if index >= tokens.count {
                break
            }

            switch tokens[index] {
            case .ampersand:
                index += 1
            case .newLine:
                index += 1
                rows.append(currentRow)
                currentRow = []
            case .command("end"):
                continue
            default:
                index += 1
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return ChatMarkdownMathMatrixNode(rows: rows, kind: matrixKind, color: textColor)
    }

    private func parseRequiredGroupText() -> String {
        guard index < tokens.count, tokens[index] == .lBrace else {
            return ""
        }

        index += 1
        var result = ""
        while index < tokens.count, tokens[index] != .rBrace {
            result += tokens[index].rawText
            index += 1
        }
        consume(.rBrace)
        return result
    }

    private func consumeDelimiterText() -> String {
        guard index < tokens.count else {
            return "."
        }

        let text = tokens[index].rawText
        index += 1
        return text
    }

    private func displayDelimiter(_ delimiter: String) -> String {
        switch delimiter {
        case ".": return ""
        case "\\{": return "{"
        case "\\}": return "}"
        default: return delimiter
        }
    }

    private func consume(_ token: ChatMarkdownLatexToken) {
        guard index < tokens.count, tokens[index] == token else {
            return
        }
        index += 1
    }
}

private extension ChatMarkdownLatexToken {
    var rawText: String {
        switch self {
        case let .command(command):
            return "\\" + command
        case let .text(text):
            return text
        case .lBrace:
            return "{"
        case .rBrace:
            return "}"
        case .hat:
            return "^"
        case .underscore:
            return "_"
        case .ampersand:
            return "&"
        case .newLine:
            return "\\\\"
        }
    }
}

private enum ChatMarkdownLatexSymbols {
    static let verticalLimits: Set<String> = ["sum", "prod", "coprod", "lim", "max", "min", "sup", "inf"]
    static let functions: Set<String> = ["sin", "cos", "tan", "log", "ln", "exp", "det", "dim", "mod", "gcd"]

    static let map: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "Gamma": "Γ",
        "delta": "δ", "Delta": "Δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "Theta": "Θ", "vartheta": "ϑ",
        "iota": "ι", "kappa": "κ", "lambda": "λ", "Lambda": "Λ",
        "mu": "μ", "nu": "ν", "xi": "ξ", "Xi": "Ξ", "pi": "π", "Pi": "Π",
        "rho": "ρ", "sigma": "σ", "Sigma": "Σ", "tau": "τ",
        "upsilon": "υ", "phi": "φ", "Phi": "Φ", "varphi": "ϕ",
        "chi": "χ", "psi": "ψ", "Psi": "Ψ", "omega": "ω", "Omega": "Ω",
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬",
        "iiint": "∭", "oint": "∮", "approx": "≈", "neq": "≠", "ne": "≠",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "equiv": "≡",
        "sim": "∼", "cong": "≅", "propto": "∝", "in": "∈", "notin": "∉",
        "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "supseteq": "⊇",
        "perp": "⊥", "parallel": "∥", "rightarrow": "→", "to": "→",
        "leftarrow": "←", "longrightarrow": "⟶", "longleftarrow": "⟵",
        "Rightarrow": "⇒", "Leftarrow": "⇐", "iff": "⇔", "leftrightarrow": "↔",
        "uparrow": "↑", "downarrow": "↓", "infty": "∞", "forall": "∀",
        "exists": "∃", "emptyset": "∅", "empty": "∅", "therefore": "∴",
        "because": "∵", "partial": "∂", "nabla": "∇", "hbar": "ℏ",
        "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "angle": "∠", "degree": "°",
        "triangle": "△", "cdot": "·", "cdots": "⋯", "vdots": "⋮",
        "ddots": "⋱", "times": "×", "div": "÷", "pm": "±", "mp": "∓",
        "ast": "*", "star": "⋆", "circ": "∘", "bullet": "•",
        "cup": "∪", "cap": "∩", "vee": "∨", "wedge": "∧",
        "oplus": "⊕", "otimes": "⊗"
    ]
}

private enum ChatMarkdownLatexFont {
    static func main(size: CGFloat) -> UIFont {
        UIFont(name: "KaTeX_Main-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    static func mainBold(size: CGFloat) -> UIFont {
        UIFont(name: "KaTeX_Main-Bold", size: size) ?? .boldSystemFont(ofSize: size)
    }

    static func mainItalic(size: CGFloat) -> UIFont {
        UIFont(name: "KaTeX_Main-Italic", size: size) ?? .italicSystemFont(ofSize: size)
    }

    static func mathItalic(size: CGFloat) -> UIFont {
        UIFont(name: "KaTeX_Math-Italic", size: size) ?? .italicSystemFont(ofSize: size)
    }

    static func ams(size: CGFloat) -> UIFont {
        UIFont(name: "KaTeX_AMS-Regular", size: size) ?? main(size: size)
    }

    static func caligraphic(size: CGFloat) -> UIFont {
        UIFont(name: "KaTeX_Caligraphic-Regular", size: size) ?? mainItalic(size: size)
    }

    static func font(forLiteral text: String, size: CGFloat) -> UIFont {
        guard let first = text.first else {
            return main(size: size)
        }

        if text.count == 1, first.isLetter {
            return mathItalic(size: size)
        }
        return main(size: size)
    }
}

private protocol ChatMarkdownMathNode {
    var size: CGSize { get }
    var baseline: CGFloat { get }
    func draw(in context: CGContext, at point: CGPoint)
}

private final class ChatMarkdownMathTextNode: ChatMarkdownMathNode {
    let text: String
    let font: UIFont
    let color: UIColor
    let size: CGSize
    let baseline: CGFloat

    init(text: String, font: UIFont, color: UIColor) {
        self.text = text
        self.font = font
        self.color = color

        let measuredSize = (text as NSString).size(withAttributes: [.font: font])
        size = CGSize(
            width: ceil(measuredSize.width),
            height: ceil(max(measuredSize.height, font.ascender - font.descender))
        )
        baseline = ceil(font.ascender)
    }

    func draw(in context: CGContext, at point: CGPoint) {
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }
}

private final class ChatMarkdownMathSpaceNode: ChatMarkdownMathNode {
    let size: CGSize
    let baseline: CGFloat = 0.0

    init(width: CGFloat) {
        size = CGSize(width: width, height: 0.0)
    }

    func draw(in context: CGContext, at point: CGPoint) {}
}

private final class ChatMarkdownMathHorizontalNode: ChatMarkdownMathNode {
    let children: [ChatMarkdownMathNode]
    let size: CGSize
    let baseline: CGFloat

    init(children: [ChatMarkdownMathNode]) {
        self.children = children
        baseline = children.map(\.baseline).max() ?? 0.0
        let descent = children.map { $0.size.height - $0.baseline }.max() ?? 0.0
        size = CGSize(
            width: children.reduce(0.0) { $0 + $1.size.width },
            height: baseline + descent
        )
    }

    func draw(in context: CGContext, at point: CGPoint) {
        var x = point.x
        for child in children {
            let y = point.y + baseline - child.baseline
            child.draw(in: context, at: CGPoint(x: x, y: y))
            x += child.size.width
        }
    }
}

private final class ChatMarkdownMathScriptsNode: ChatMarkdownMathNode {
    let base: ChatMarkdownMathNode
    let upper: ChatMarkdownMathNode?
    let lower: ChatMarkdownMathNode?
    let size: CGSize
    let baseline: CGFloat

    init(
        base: ChatMarkdownMathNode,
        upper: ChatMarkdownMathNode?,
        lower: ChatMarkdownMathNode?
    ) {
        self.base = base
        self.upper = upper
        self.lower = lower

        let upperLift = upper.map { max(0.0, $0.size.height - base.size.height * 0.35) } ?? 0.0
        baseline = upperLift + base.baseline
        let scriptWidth = max(upper?.size.width ?? 0.0, lower?.size.width ?? 0.0)
        let lowerDepth = lower.map { $0.size.height * 0.85 } ?? 0.0
        size = CGSize(
            width: base.size.width + scriptWidth,
            height: max(upperLift + base.size.height, baseline + lowerDepth)
        )
    }

    func draw(in context: CGContext, at point: CGPoint) {
        let baseY = point.y + baseline - base.baseline
        base.draw(in: context, at: CGPoint(x: point.x, y: baseY))

        let scriptX = point.x + base.size.width
        if let upper {
            upper.draw(in: context, at: CGPoint(x: scriptX, y: point.y))
        }
        if let lower {
            lower.draw(
                in: context,
                at: CGPoint(x: scriptX, y: point.y + baseline - lower.baseline + lower.size.height * 0.28)
            )
        }
    }
}

private final class ChatMarkdownMathLimitsNode: ChatMarkdownMathNode {
    let base: ChatMarkdownMathNode
    let upper: ChatMarkdownMathNode?
    let lower: ChatMarkdownMathNode?
    let size: CGSize
    let baseline: CGFloat
    private let gap: CGFloat = 2.0

    init(base: ChatMarkdownMathNode, upper: ChatMarkdownMathNode?, lower: ChatMarkdownMathNode?) {
        self.base = base
        self.upper = upper
        self.lower = lower

        let upperHeight = upper?.size.height ?? 0.0
        let lowerHeight = lower?.size.height ?? 0.0
        let width = max(base.size.width, max(upper?.size.width ?? 0.0, lower?.size.width ?? 0.0)) + 2.0
        baseline = upperHeight + (upper == nil ? 0.0 : gap) + base.baseline
        size = CGSize(
            width: width,
            height: upperHeight +
                (upper == nil ? 0.0 : gap) +
                base.size.height +
                (lower == nil ? 0.0 : gap) +
                lowerHeight
        )
    }

    func draw(in context: CGContext, at point: CGPoint) {
        let centerX = point.x + size.width / 2.0
        var y = point.y

        if let upper {
            upper.draw(in: context, at: CGPoint(x: centerX - upper.size.width / 2.0, y: y))
            y += upper.size.height + gap
        }

        base.draw(in: context, at: CGPoint(x: centerX - base.size.width / 2.0, y: y))
        y += base.size.height + gap

        if let lower {
            lower.draw(in: context, at: CGPoint(x: centerX - lower.size.width / 2.0, y: y))
        }
    }
}

private final class ChatMarkdownMathFractionNode: ChatMarkdownMathNode {
    let numerator: ChatMarkdownMathNode
    let denominator: ChatMarkdownMathNode
    let color: UIColor
    let size: CGSize
    let baseline: CGFloat
    private let gap: CGFloat = 3.0
    private let ruleHeight: CGFloat = 1.0

    init(numerator: ChatMarkdownMathNode, denominator: ChatMarkdownMathNode, color: UIColor) {
        self.numerator = numerator
        self.denominator = denominator
        self.color = color
        let width = max(numerator.size.width, denominator.size.width) + 8.0
        baseline = numerator.size.height + gap + ruleHeight
        size = CGSize(
            width: width,
            height: numerator.size.height + denominator.size.height + gap * 2.0 + ruleHeight
        )
    }

    func draw(in context: CGContext, at point: CGPoint) {
        numerator.draw(
            in: context,
            at: CGPoint(x: point.x + (size.width - numerator.size.width) / 2.0, y: point.y)
        )

        let ruleY = point.y + numerator.size.height + gap
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(ruleHeight)
        context.move(to: CGPoint(x: point.x, y: ruleY))
        context.addLine(to: CGPoint(x: point.x + size.width, y: ruleY))
        context.strokePath()

        denominator.draw(
            in: context,
            at: CGPoint(
                x: point.x + (size.width - denominator.size.width) / 2.0,
                y: ruleY + gap
            )
        )
    }
}

private final class ChatMarkdownMathSqrtNode: ChatMarkdownMathNode {
    let inner: ChatMarkdownMathNode
    let color: UIColor
    let size: CGSize
    let baseline: CGFloat

    init(inner: ChatMarkdownMathNode, color: UIColor) {
        self.inner = inner
        self.color = color
        size = CGSize(width: inner.size.width + 12.0, height: inner.size.height + 5.0)
        baseline = inner.baseline + 5.0
    }

    func draw(in context: CGContext, at point: CGPoint) {
        inner.draw(in: context, at: CGPoint(x: point.x + 11.0, y: point.y + 5.0))

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.2)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: point.x + 1.0, y: point.y + size.height * 0.62))
        context.addLine(to: CGPoint(x: point.x + 5.0, y: point.y + size.height - 1.0))
        context.addLine(to: CGPoint(x: point.x + 11.0, y: point.y + 1.0))
        context.addLine(to: CGPoint(x: point.x + size.width, y: point.y + 1.0))
        context.strokePath()
    }
}

private final class ChatMarkdownMathBinomNode: ChatMarkdownMathNode {
    let numerator: ChatMarkdownMathNode
    let denominator: ChatMarkdownMathNode
    let color: UIColor
    let size: CGSize
    let baseline: CGFloat

    init(numerator: ChatMarkdownMathNode, denominator: ChatMarkdownMathNode, color: UIColor) {
        self.numerator = numerator
        self.denominator = denominator
        self.color = color
        let contentWidth = max(numerator.size.width, denominator.size.width)
        size = CGSize(width: contentWidth + 16.0, height: numerator.size.height + denominator.size.height + 4.0)
        baseline = numerator.size.height + 2.0
    }

    func draw(in context: CGContext, at point: CGPoint) {
        let centerX = point.x + size.width / 2.0
        numerator.draw(in: context, at: CGPoint(x: centerX - numerator.size.width / 2.0, y: point.y))
        denominator.draw(
            in: context,
            at: CGPoint(x: centerX - denominator.size.width / 2.0, y: point.y + numerator.size.height + 4.0)
        )
        ChatMarkdownMathDelimiterDrawing.drawParens(
            in: context,
            rect: CGRect(origin: point, size: size),
            color: color
        )
    }
}

private final class ChatMarkdownMathEnclosureNode: ChatMarkdownMathNode {
    enum Kind {
        case overline
        case underline
        case boxed
    }

    let child: ChatMarkdownMathNode
    let kind: Kind
    let color: UIColor
    let size: CGSize
    let baseline: CGFloat

    init(child: ChatMarkdownMathNode, kind: Kind, color: UIColor) {
        self.child = child
        self.kind = kind
        self.color = color

        switch kind {
        case .overline:
            size = CGSize(width: child.size.width, height: child.size.height + 4.0)
            baseline = child.baseline + 4.0
        case .underline:
            size = CGSize(width: child.size.width, height: child.size.height + 4.0)
            baseline = child.baseline
        case .boxed:
            size = CGSize(width: child.size.width + 8.0, height: child.size.height + 8.0)
            baseline = child.baseline + 4.0
        }
    }

    func draw(in context: CGContext, at point: CGPoint) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.0)

        switch kind {
        case .overline:
            child.draw(in: context, at: CGPoint(x: point.x, y: point.y + 4.0))
            context.move(to: CGPoint(x: point.x, y: point.y + 1.0))
            context.addLine(to: CGPoint(x: point.x + size.width, y: point.y + 1.0))
            context.strokePath()
        case .underline:
            child.draw(in: context, at: point)
            context.move(to: CGPoint(x: point.x, y: point.y + size.height - 1.0))
            context.addLine(to: CGPoint(x: point.x + size.width, y: point.y + size.height - 1.0))
            context.strokePath()
        case .boxed:
            context.stroke(CGRect(origin: point, size: size))
            child.draw(in: context, at: CGPoint(x: point.x + 4.0, y: point.y + 4.0))
        }
    }
}

private final class ChatMarkdownMathMatrixNode: ChatMarkdownMathNode {
    enum Kind {
        case plain
        case paren
        case bracket
        case cases
        case verticalBars

        init(environment: String) {
            switch environment {
            case "pmatrix":
                self = .paren
            case "bmatrix":
                self = .bracket
            case "cases":
                self = .cases
            case "vmatrix":
                self = .verticalBars
            default:
                self = .plain
            }
        }
    }

    let rows: [[ChatMarkdownMathNode]]
    let kind: Kind
    let color: UIColor
    let size: CGSize
    let baseline: CGFloat
    private let columnWidths: [CGFloat]
    private let rowHeights: [CGFloat]
    private let rowBaselines: [CGFloat]
    private let delimiterWidth: CGFloat
    private let columnSpacing: CGFloat = 10.0
    private let rowSpacing: CGFloat = 4.0

    init(rows: [[ChatMarkdownMathNode]], kind: Kind, color: UIColor) {
        self.rows = rows
        self.kind = kind
        self.color = color

        let columnCount = rows.map(\.count).max() ?? 0
        var columnWidths = Array(repeating: CGFloat(0.0), count: columnCount)
        for row in rows {
            for column in row.indices {
                columnWidths[column] = max(columnWidths[column], row[column].size.width)
            }
        }
        self.columnWidths = columnWidths

        let calculatedRowBaselines = rows.map { row in row.map(\.baseline).max() ?? 0.0 }
        let calculatedRowHeights = rows.enumerated().map { offset, row in
            let baseline = calculatedRowBaselines[offset]
            let descent = row.map { $0.size.height - $0.baseline }.max() ?? 0.0
            return baseline + descent
        }
        rowBaselines = calculatedRowBaselines
        rowHeights = calculatedRowHeights

        delimiterWidth = kind == .plain ? 0.0 : 8.0
        let contentWidth = columnWidths.reduce(0.0, +) + max(0.0, CGFloat(columnWidths.count - 1)) * columnSpacing
        let contentHeight = rowHeights.reduce(0.0, +) + max(0.0, CGFloat(rowHeights.count - 1)) * rowSpacing
        size = CGSize(width: contentWidth + delimiterWidth * 2.0, height: contentHeight)
        baseline = size.height * 0.56
    }

    func draw(in context: CGContext, at point: CGPoint) {
        let contentOriginX = point.x + delimiterWidth
        var rowY = point.y

        for rowIndex in rows.indices {
            var x = contentOriginX
            let row = rows[rowIndex]
            for columnIndex in columnWidths.indices {
                if columnIndex < row.count {
                    let cell = row[columnIndex]
                    let cellX = x + (columnWidths[columnIndex] - cell.size.width) / 2.0
                    let cellY = rowY + rowBaselines[rowIndex] - cell.baseline
                    cell.draw(in: context, at: CGPoint(x: cellX, y: cellY))
                }
                x += columnWidths[columnIndex] + columnSpacing
            }
            rowY += rowHeights[rowIndex] + rowSpacing
        }

        let rect = CGRect(origin: point, size: size)
        switch kind {
        case .plain:
            break
        case .paren:
            ChatMarkdownMathDelimiterDrawing.drawParens(in: context, rect: rect, color: color)
        case .bracket:
            ChatMarkdownMathDelimiterDrawing.drawBrackets(in: context, rect: rect, color: color)
        case .cases:
            ChatMarkdownMathDelimiterDrawing.drawLeftBrace(in: context, rect: rect, color: color)
        case .verticalBars:
            ChatMarkdownMathDelimiterDrawing.drawVerticalBars(in: context, rect: rect, color: color)
        }
    }
}

private enum ChatMarkdownMathDelimiterDrawing {
    static func drawParens(in context: CGContext, rect: CGRect, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.1)
        context.move(to: CGPoint(x: rect.minX + 6.0, y: rect.minY))
        context.addQuadCurve(
            to: CGPoint(x: rect.minX + 6.0, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.midY)
        )
        context.move(to: CGPoint(x: rect.maxX - 6.0, y: rect.minY))
        context.addQuadCurve(
            to: CGPoint(x: rect.maxX - 6.0, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        context.strokePath()
    }

    static func drawBrackets(in context: CGContext, rect: CGRect, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.1)
        let inset: CGFloat = 2.0
        context.move(to: CGPoint(x: rect.minX + 7.0, y: rect.minY + inset))
        context.addLine(to: CGPoint(x: rect.minX + 2.0, y: rect.minY + inset))
        context.addLine(to: CGPoint(x: rect.minX + 2.0, y: rect.maxY - inset))
        context.addLine(to: CGPoint(x: rect.minX + 7.0, y: rect.maxY - inset))
        context.move(to: CGPoint(x: rect.maxX - 7.0, y: rect.minY + inset))
        context.addLine(to: CGPoint(x: rect.maxX - 2.0, y: rect.minY + inset))
        context.addLine(to: CGPoint(x: rect.maxX - 2.0, y: rect.maxY - inset))
        context.addLine(to: CGPoint(x: rect.maxX - 7.0, y: rect.maxY - inset))
        context.strokePath()
    }

    static func drawLeftBrace(in context: CGContext, rect: CGRect, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.1)
        let x = rect.minX + 7.0
        let midY = rect.midY
        context.move(to: CGPoint(x: x, y: rect.minY))
        context.addCurve(
            to: CGPoint(x: x - 5.0, y: midY),
            control1: CGPoint(x: x - 5.0, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: x - 5.0, y: midY - rect.height * 0.12)
        )
        context.addCurve(
            to: CGPoint(x: x, y: rect.maxY),
            control1: CGPoint(x: x - 5.0, y: midY + rect.height * 0.12),
            control2: CGPoint(x: x - 5.0, y: rect.maxY - rect.height * 0.18)
        )
        context.strokePath()
    }

    static func drawVerticalBars(in context: CGContext, rect: CGRect, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.1)
        context.move(to: CGPoint(x: rect.minX + 3.0, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.minX + 3.0, y: rect.maxY))
        context.move(to: CGPoint(x: rect.maxX - 3.0, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX - 3.0, y: rect.maxY))
        context.strokePath()
    }
}
