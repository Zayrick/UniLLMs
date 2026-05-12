//
//  ChatMarkdownRenderer.swift
//  UniLLMs
//
//  Renders chat Markdown into attributed text using swift-markdown.
//  Created by Codex on 2026/5/12.
//

import Markdown
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

struct ChatMarkdownRenderer {
    private static let parseLock = NSLock()

    private let style: ChatMarkdownRenderStyle
    private var listDepth = 0
    private var orderedListCounters: [Int] = []

    init(style: ChatMarkdownRenderStyle = .assistant) {
        self.style = style
    }

    mutating func render(markdown: String) -> NSAttributedString {
        guard !markdown.isEmpty else {
            return NSAttributedString()
        }

        let document = Self.parseDocument(markdown)
        let result = NSMutableAttributedString()

        for child in document.children {
            result.append(renderBlock(child))
        }

        trimTrailingNewlines(in: result)
        return result
    }

    private static func parseDocument(_ markdown: String) -> Document {
        parseLock.lock()
        defer { parseLock.unlock() }
        return Document(parsing: markdown)
    }

    private mutating func renderBlocks(_ children: MarkupChildren) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            result.append(renderBlock(child))
        }
        return result
    }

    private mutating func renderBlock(_ markup: any Markup) -> NSMutableAttributedString {
        switch markup {
        case let heading as Heading:
            return renderHeading(heading)
        case let paragraph as Paragraph:
            return renderParagraph(paragraph)
        case let unorderedList as UnorderedList:
            return renderUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            return renderOrderedList(orderedList)
        case let codeBlock as CodeBlock:
            return renderCodeBlock(codeBlock)
        case let quote as BlockQuote:
            return renderBlockQuote(quote)
        case let table as Table:
            return renderTable(table)
        case _ as ThematicBreak:
            return blockString("---\n", attributes: Self.secondaryAttributes(style: style))
        case let htmlBlock as HTMLBlock:
            return blockString(htmlBlock.rawHTML + "\n", attributes: Self.secondaryAttributes(style: style))
        case let image as Markdown.Image:
            return blockString(imageDisplayText(source: image.source, altText: image.plainText) + "\n", attributes: Self.secondaryAttributes(style: style))
        default:
            let result = NSMutableAttributedString()
            for child in markup.children {
                result.append(renderBlock(child))
            }
            return result
        }
    }

    private mutating func renderHeading(_ heading: Heading) -> NSMutableAttributedString {
        let result = renderInlineChildren(of: heading)
        appendNewlineIfNeeded(to: result)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.paragraphSpacingBefore = heading.level == 1 ? 7.0 : 5.0
        paragraphStyle.paragraphSpacing = 4.0

        apply(
            [
                .font: style.headingFont(level: heading.level),
                .foregroundColor: style.textColor,
                .paragraphStyle: paragraphStyle
            ],
            to: result
        )
        return result
    }

    private mutating func renderParagraph(_ paragraph: Paragraph) -> NSMutableAttributedString {
        let result = renderInlineChildren(of: paragraph)
        appendNewlineIfNeeded(to: result)
        applyParagraphStyle(to: result, spacing: 4.0)
        return result
    }

    private mutating func renderUnorderedList(_ list: UnorderedList) -> NSMutableAttributedString {
        listDepth += 1
        defer { listDepth -= 1 }
        return renderListItems(list.listItems, isOrdered: false)
    }

    private mutating func renderOrderedList(_ list: OrderedList) -> NSMutableAttributedString {
        listDepth += 1
        orderedListCounters.append(Int(list.startIndex))
        defer {
            orderedListCounters.removeLast()
            listDepth -= 1
        }

        return renderListItems(list.listItems, isOrdered: true)
    }

    private mutating func renderListItems<Items: Sequence>(
        _ items: Items,
        isOrdered: Bool
    ) -> NSMutableAttributedString where Items.Element == ListItem {
        let result = NSMutableAttributedString()

        for item in items {
            let marker: String
            if isOrdered {
                let current = orderedListCounters.last ?? 1
                marker = "\(current)."
                if !orderedListCounters.isEmpty {
                    orderedListCounters[orderedListCounters.count - 1] = current + 1
                }
            } else if let checkbox = item.checkbox {
                marker = checkbox == .checked ? "[x]" : "[ ]"
            } else {
                marker = "-"
            }

            let itemText = renderBlocks(item.children)
            trimTrailingNewlines(in: itemText)

            let itemResult = NSMutableAttributedString(
                string: "\(marker) ",
                attributes: Self.bodyAttributes(style: style)
            )
            itemResult.append(itemText)
            appendNewlineIfNeeded(to: itemResult)

            let paragraphStyle = NSMutableParagraphStyle()
            let markerWidth = max(CGFloat(marker.count) * 8.0 + 12.0, 24.0)
            let indent = CGFloat(max(0, listDepth - 1)) * 18.0
            paragraphStyle.firstLineHeadIndent = indent
            paragraphStyle.headIndent = indent + markerWidth
            paragraphStyle.paragraphSpacing = 2.0
            apply([.paragraphStyle: paragraphStyle], to: itemResult)

            result.append(itemResult)
        }

        if listDepth == 1 {
            result.append(NSAttributedString(string: "\n"))
        }

        return result
    }

    private mutating func renderCodeBlock(_ codeBlock: CodeBlock) -> NSMutableAttributedString {
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = language?.isEmpty == false ? "\(language!)\n" : ""
        let text = header + code + "\n"

        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: style.codeFont,
                .foregroundColor: style.codeTextColor,
                .backgroundColor: style.codeBackgroundColor
            ]
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.0
        paragraphStyle.paragraphSpacingBefore = 4.0
        paragraphStyle.paragraphSpacing = 6.0
        apply([.paragraphStyle: paragraphStyle], to: result)
        return result
    }

    private mutating func renderBlockQuote(_ quote: BlockQuote) -> NSMutableAttributedString {
        let result = renderBlocks(quote.children)
        trimTrailingNewlines(in: result)
        appendNewlineIfNeeded(to: result)

        apply(
            [
                .foregroundColor: style.secondaryTextColor,
                .font: style.calloutFont
            ],
            to: result
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 12.0
        paragraphStyle.headIndent = 12.0
        paragraphStyle.paragraphSpacing = 4.0
        apply([.paragraphStyle: paragraphStyle], to: result)
        return result
    }

    private mutating func renderTable(_ table: Table) -> NSMutableAttributedString {
        var rows: [[String]] = []
        rows.append(table.head.cells.map { cell in
            renderPlainCell(cell)
        })
        for row in table.body.rows {
            rows.append(row.cells.map { cell in
                renderPlainCell(cell)
            })
        }

        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else {
            return NSMutableAttributedString()
        }

        let widths = (0..<columnCount).map { column in
            rows.map { row in
                column < row.count ? row[column].count : 0
            }.max() ?? 0
        }

        let text = rows.enumerated().map { index, row in
            let padded = (0..<columnCount).map { column -> String in
                let value = column < row.count ? row[column] : ""
                return value.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }
            let line = "| " + padded.joined(separator: " | ") + " |"
            if index == 0 {
                let divider = "| " + widths.map { String(repeating: "-", count: max(3, $0)) }.joined(separator: " | ") + " |"
                return line + "\n" + divider
            }
            return line
        }.joined(separator: "\n") + "\n"

        return blockString(
            text,
            attributes: [
                .font: style.codeFont,
                .foregroundColor: style.textColor,
                .backgroundColor: style.codeBackgroundColor
            ],
            paragraphSpacing: 6.0
        )
    }

    private mutating func renderPlainCell(_ cell: Table.Cell) -> String {
        let attributed = renderInlineChildren(of: cell)
        return attributed.string
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func renderInlineChildren(of markup: any Markup) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(renderInline(child))
        }
        return result
    }

    private mutating func renderInline(_ markup: any Markup) -> NSMutableAttributedString {
        switch markup {
        case let text as Text:
            return NSMutableAttributedString(string: text.string, attributes: Self.bodyAttributes(style: style))
        case let strong as Strong:
            let result = renderInlineChildren(of: strong)
            apply([.font: boldFont(from: style.bodyFont)], to: result)
            return result
        case let emphasis as Emphasis:
            let result = renderInlineChildren(of: emphasis)
            apply([.font: italicFont(from: style.bodyFont)], to: result)
            return result
        case let strikethrough as Strikethrough:
            let result = renderInlineChildren(of: strikethrough)
            apply([.strikethroughStyle: NSUnderlineStyle.single.rawValue], to: result)
            return result
        case let inlineCode as InlineCode:
            return NSMutableAttributedString(
                string: inlineCode.code,
                attributes: [
                    .font: style.codeFont,
                    .foregroundColor: style.codeTextColor,
                    .backgroundColor: style.codeBackgroundColor
                ]
            )
        case let link as Link:
            let result = renderInlineChildren(of: link)
            apply(
                [
                    .foregroundColor: style.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                to: result
            )
            if let destination = link.destination,
               let url = URL(string: destination) {
                apply([.link: url], to: result)
            }
            return result
        case let image as Markdown.Image:
            return NSMutableAttributedString(
                string: imageDisplayText(source: image.source, altText: image.plainText),
                attributes: Self.secondaryAttributes(style: style)
            )
        case _ as SoftBreak:
            return NSMutableAttributedString(string: " ", attributes: Self.bodyAttributes(style: style))
        case _ as LineBreak:
            return NSMutableAttributedString(string: "\n", attributes: Self.bodyAttributes(style: style))
        case let html as InlineHTML:
            return NSMutableAttributedString(string: html.rawHTML, attributes: Self.secondaryAttributes(style: style))
        case let unorderedList as UnorderedList:
            return renderUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            return renderOrderedList(orderedList)
        case let paragraph as Paragraph:
            return renderParagraph(paragraph)
        default:
            return renderInlineChildren(of: markup)
        }
    }

    private func blockString(
        _ string: String,
        attributes: [NSAttributedString.Key: Any],
        paragraphSpacing: CGFloat = 4.0
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: string, attributes: attributes)
        applyParagraphStyle(to: result, spacing: paragraphSpacing)
        return result
    }

    private func applyParagraphStyle(to attributedString: NSMutableAttributedString, spacing: CGFloat) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.paragraphSpacing = spacing
        apply([.paragraphStyle: paragraphStyle], to: attributedString)
    }

    private func appendNewlineIfNeeded(to attributedString: NSMutableAttributedString) {
        guard attributedString.length == 0 || !attributedString.string.hasSuffix("\n") else {
            return
        }

        attributedString.append(NSAttributedString(string: "\n", attributes: Self.bodyAttributes(style: style)))
    }

    private func trimTrailingNewlines(in attributedString: NSMutableAttributedString) {
        while attributedString.length > 0 && attributedString.string.hasSuffix("\n") {
            attributedString.deleteCharacters(in: NSRange(location: attributedString.length - 1, length: 1))
        }
    }

    private func apply(_ attributes: [NSAttributedString.Key: Any], to attributedString: NSMutableAttributedString) {
        guard attributedString.length > 0 else {
            return
        }

        attributedString.addAttributes(attributes, range: NSRange(location: 0, length: attributedString.length))
    }

    private func boldFont(from font: UIFont) -> UIFont {
        font.withSymbolicTraits(.traitBold) ?? .boldSystemFont(ofSize: font.pointSize)
    }

    private func italicFont(from font: UIFont) -> UIFont {
        font.withSymbolicTraits(.traitItalic) ?? .italicSystemFont(ofSize: font.pointSize)
    }

    private func imageDisplayText(source: String?, altText: String) -> String {
        let label = altText.isEmpty ? "Image" : altText
        guard let source,
              !source.isEmpty else {
            return "[\(label)]"
        }

        return "[\(label): \(source)]"
    }

    private static func bodyAttributes(style: ChatMarkdownRenderStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: style.bodyFont,
            .foregroundColor: style.textColor
        ]
    }

    private static func secondaryAttributes(style: ChatMarkdownRenderStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: style.calloutFont,
            .foregroundColor: style.secondaryTextColor
        ]
    }
}

private extension UIFont {
    func withSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return nil
        }

        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
