//
//  StreamingMarkdownTableRenderer.swift
//  UniLLMs
//
//  Incremental pipe-table renderer for open streamed Markdown tables.
//
//  Created by Codex on 2026/5/21.
//

import UIKit

final class StreamingMarkdownTableRenderer {
    private let context: ChatMarkdownRenderingContext
    private let inlineRenderer: StreamingMarkdownInlineRenderer

    init(context: ChatMarkdownRenderingContext) {
        self.context = context
        inlineRenderer = StreamingMarkdownInlineRenderer(context: context)
    }

    func renderTableData(fromMarkdown markdown: String, isOpen: Bool) -> ChatMarkdownTableData? {
        let lines = Self.displayLines(in: markdown)
        guard lines.count >= 2,
              IncrementalMarkdownLineParser.detectTableStart(lines: Array(lines.prefix(2))) else {
            return nil
        }

        let headerCells = Self.cells(in: lines[0])
        let alignments = Self.alignments(in: lines[1])
        let bodyRows = lines.dropFirst(2).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let parsedRows = [headerCells] + bodyRows.map { Self.cells(in: $0) }
        let columnCount = max(
            headerCells.count,
            max(alignments.count, parsedRows.map(\.count).max() ?? 0)
        )
        guard columnCount > 0 else {
            return nil
        }

        let rows = parsedRows.enumerated().map { rowIndex, row in
            renderRow(
                row,
                columnCount: columnCount,
                alignments: alignments,
                isHeader: rowIndex == 0,
                allowPrediction: isOpen && rowIndex == parsedRows.count - 1
            )
        }
        return ChatMarkdownTableData(rows: rows, columnCount: columnCount)
    }

    private func renderRow(
        _ row: [String],
        columnCount: Int,
        alignments: [NSTextAlignment],
        isHeader: Bool,
        allowPrediction: Bool
    ) -> [ChatMarkdownTableCell] {
        (0..<columnCount).map { column in
            let text = column < row.count ? row[column] : ""
            let alignment = column < alignments.count ? alignments[column] : .left
            return renderCell(
                text,
                alignment: alignment,
                isHeader: isHeader,
                allowPrediction: allowPrediction
            )
        }
    }

    private func renderCell(
        _ text: String,
        alignment: NSTextAlignment,
        isHeader: Bool,
        allowPrediction: Bool
    ) -> ChatMarkdownTableCell {
        let attributed = inlineRenderer.render(
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            allowPrediction: allowPrediction
        )
        trimOuterWhitespace(in: attributed)
        applyParagraphStyle(to: attributed, alignment: alignment)
        if isHeader {
            applyHeaderFont(to: attributed)
        }
        return ChatMarkdownTableCell(
            attributedText: attributed,
            alignment: alignment,
            isHeader: isHeader
        )
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineSpacing = context.style.compactLineSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacing = 0.0

        if attributedString.length == 0 {
            attributedString.append(
                NSAttributedString(string: "", attributes: context.bodyAttributes())
            )
            return
        }
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
}

private extension StreamingMarkdownTableRenderer {
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

    static func cells(in row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var index = row.startIndex
        var backtickRun = 0

        while index < row.endIndex {
            let character = row[index]
            if character == "\\" {
                let next = row.index(after: index)
                if next < row.endIndex {
                    current.append(row[next])
                    index = row.index(after: next)
                } else {
                    current.append(character)
                    index = next
                }
                continue
            }

            if character == "`" {
                let run = countRepeated("`", in: row, from: index)
                if backtickRun == run {
                    backtickRun = 0
                } else if backtickRun == 0 {
                    backtickRun = run
                }
                current.append(contentsOf: String(repeating: "`", count: run))
                index = row.index(index, offsetBy: run)
                continue
            }

            if character == "|", backtickRun == 0 {
                cells.append(current)
                current = ""
                index = row.index(after: index)
                continue
            }

            current.append(character)
            index = row.index(after: index)
        }

        cells.append(current)
        if cells.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            cells.removeLast()
        }
        return cells
    }

    static func alignments(in delimiter: String) -> [NSTextAlignment] {
        cells(in: delimiter).map { rawCell in
            let cell = rawCell.trimmingCharacters(in: .whitespacesAndNewlines)
            let startsWithColon = cell.hasPrefix(":")
            let endsWithColon = cell.hasSuffix(":")
            if startsWithColon, endsWithColon {
                return .center
            }
            if endsWithColon {
                return .right
            }
            return .left
        }
    }

    static func countRepeated(_ character: Character, in text: String, from start: String.Index) -> Int {
        var cursor = start
        var count = 0
        while cursor < text.endIndex, text[cursor] == character {
            count += 1
            cursor = text.index(after: cursor)
        }
        return count
    }
}
