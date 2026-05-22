//
//  ChatMarkdownHTMLTableRenderer.swift
//  UniLLMs
//
//  Converts GFM raw HTML tables into native chat table data.
//  Created by Zayrick on 2026/5/14.
//

import UIKit

final class ChatMarkdownHTMLTableRenderer {
    private struct PendingCell {
        var html = ""
        let isHeader: Bool
        let alignment: NSTextAlignment
    }

    private struct ParsedCell {
        let html: String
        let isHeader: Bool
        let alignment: NSTextAlignment
    }

    private let context: ChatMarkdownRenderingContext
    private let htmlBlockRenderer: ChatMarkdownHTMLBlockRenderer

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
        htmlBlockRenderer = ChatMarkdownHTMLBlockRenderer(context: context)
    }

    func renderTableData(fromHTML rawHTML: String) -> ChatMarkdownTableData? {
        guard rawHTML.localizedCaseInsensitiveContains("<table") else {
            return nil
        }

        let rows = parseRows(fromHTML: rawHTML)
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else {
            return nil
        }

        let renderedRows = rows.map { row in
            renderRow(row, columnCount: columnCount)
        }
        let tableData = ChatMarkdownTableData(rows: renderedRows, columnCount: columnCount)
        return tableData.isEmpty ? nil : tableData
    }

    private func parseRows(fromHTML rawHTML: String) -> [[ParsedCell]] {
        var rows: [[ParsedCell]] = []
        var currentRow: [ParsedCell] = []
        var pendingCell: PendingCell?
        var isInsideTable = false
        var isInsideRow = false

        for token in ChatMarkdownHTMLSupport.tokens(in: rawHTML) {
            switch token {
            case let .tag(tag):
                if pendingCell != nil, !isCellBoundary(tag) {
                    pendingCell?.html += tag.rawHTML
                    continue
                }

                switch tag.name {
                case "table":
                    isInsideTable = !tag.isClosing
                case "tr":
                    if tag.isClosing {
                        if !currentRow.isEmpty {
                            rows.append(currentRow)
                        }
                        currentRow = []
                        isInsideRow = false
                    } else if isInsideTable {
                        if !currentRow.isEmpty {
                            rows.append(currentRow)
                            currentRow = []
                        }
                        isInsideRow = true
                    }
                case "td", "th":
                    if tag.isClosing {
                        if let cell = pendingCell {
                            currentRow.append(
                                ParsedCell(
                                    html: cell.html,
                                    isHeader: cell.isHeader,
                                    alignment: cell.alignment
                                )
                            )
                            pendingCell = nil
                        }
                    } else if isInsideTable {
                        if !isInsideRow {
                            isInsideRow = true
                            currentRow = []
                        }
                        pendingCell = PendingCell(
                            isHeader: tag.name == "th",
                            alignment: alignment(from: tag.attribute("align"))
                        )
                    }
                default:
                    continue
                }
            case let .text(text), let .cdata(text):
                pendingCell?.html += text
            case let .comment(raw), let .declaration(raw), let .processingInstruction(raw):
                pendingCell?.html += raw
            }
        }

        if let cell = pendingCell {
            currentRow.append(
                ParsedCell(
                    html: cell.html,
                    isHeader: cell.isHeader,
                    alignment: cell.alignment
                )
            )
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private func isCellBoundary(_ tag: ChatMarkdownHTMLTag) -> Bool {
        tag.name == "td" || tag.name == "th"
    }

    private func renderRow(
        _ row: [ParsedCell],
        columnCount: Int
    ) -> [ChatMarkdownTableCell] {
        (0..<columnCount).map { column in
            guard column < row.count else {
                return ChatMarkdownTableCell(
                    attributedText: NSAttributedString(string: "", attributes: context.bodyAttributes()),
                    alignment: .left,
                    isHeader: false
                )
            }

            return renderCell(row[column])
        }
    }

    private func renderCell(_ cell: ParsedCell) -> ChatMarkdownTableCell {
        let attributedText = htmlBlockRenderer.renderHTMLBlock(cell.html)
        context.trimTrailingNewlines(in: attributedText)
        replaceNewlinesWithSpaces(in: attributedText)
        trimOuterWhitespace(in: attributedText)
        applyParagraphStyle(to: attributedText, alignment: cell.alignment)

        if cell.isHeader {
            applyHeaderFont(to: attributedText)
        }

        return ChatMarkdownTableCell(
            attributedText: attributedText,
            alignment: cell.alignment,
            isHeader: cell.isHeader
        )
    }

    private func replaceNewlinesWithSpaces(in attributedString: NSMutableAttributedString) {
        while true {
            let range = (attributedString.string as NSString).range(of: "\n")
            guard range.location != NSNotFound else {
                return
            }

            attributedString.replaceCharacters(in: range, with: " ")
        }
    }

    private func trimOuterWhitespace(in attributedString: NSMutableAttributedString) {
        while attributedString.length > 0,
              let first = attributedString.string.first,
              first.isWhitespace {
            attributedString.deleteCharacters(in: NSRange(location: 0, length: 1))
        }

        while attributedString.length > 0,
              let last = attributedString.string.last,
              last.isWhitespace {
            attributedString.deleteCharacters(in: NSRange(location: attributedString.length - 1, length: 1))
        }
    }

    private func applyParagraphStyle(
        to attributedString: NSMutableAttributedString,
        alignment: NSTextAlignment
    ) {
        guard attributedString.length > 0 else {
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineSpacing = context.style.compactLineSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacing = 0.0
        attributedString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributedString.length)
        )
    }

    private func applyHeaderFont(to attributedString: NSMutableAttributedString) {
        guard attributedString.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let font = (value as? UIFont) ?? context.currentBodyFont()
            attributedString.addAttribute(
                .font,
                value: ChatMarkdownFontTraits.adding(.traitBold, to: font),
                range: range
            )
        }
    }

    private func alignment(from value: String?) -> NSTextAlignment {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "center", "middle":
            return .center
        case "right":
            return .right
        default:
            return .left
        }
    }
}
