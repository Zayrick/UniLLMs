//
//  ChatMarkdownRenderer+Tables.swift
//  UniLLMs
//
//  Table Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

enum ChatMarkdownTableLayoutMetrics {
    static let minColumnWidth: CGFloat = 64.0
    static let maxColumnWidth: CGFloat = 280.0
    static let cellHorizontalPadding: CGFloat = 10.0
    static let cellVerticalPadding: CGFloat = 8.0
    static let minRowHeight: CGFloat = 34.0
    static let verticalMargin: CGFloat = 4.0
    static let cornerRadius: CGFloat = 7.0
    static let paragraphSpacing: CGFloat = 7.0
}

extension ChatMarkdownRenderer {
    mutating func renderTable(_ table: Table) -> NSMutableAttributedString {
        let tableData = renderTableData(table)
        guard !tableData.isEmpty else {
            return NSMutableAttributedString()
        }

        return renderPlainTextTable(tableData)
    }

    mutating func renderTableData(_ table: Table) -> ChatMarkdownTableData {
        let headerCells = Array(table.head.cells)
        let bodyRows = table.body.rows.map { Array($0.cells) }
        let bodyColumnCount = bodyRows.map(\.count).max() ?? 0
        let columnCount = max(max(headerCells.count, bodyColumnCount), table.columnAlignments.count)

        guard columnCount > 0 else {
            return ChatMarkdownTableData(rows: [], columnCount: 0)
        }

        let alignments = (0..<columnCount).map { column in
            textAlignment(for: table.columnAlignments[safe: column].flatMap { $0 })
        }
        var rows: [[ChatMarkdownTableCell]] = [
            renderTableRow(headerCells, columnCount: columnCount, alignments: alignments, isHeader: true)
        ]
        for row in bodyRows {
            rows.append(
                renderTableRow(row, columnCount: columnCount, alignments: alignments, isHeader: false)
            )
        }

        return ChatMarkdownTableData(rows: rows, columnCount: columnCount)
    }

    func renderPlainTextTable(_ tableData: ChatMarkdownTableData) -> NSMutableAttributedString {
        let text = tableData.rows
            .map { row in
                row.map(\.accessibilityText).joined(separator: "  ")
            }
            .joined(separator: "\n")
        let result = NSMutableAttributedString(string: text + "\n", attributes: bodyAttributes())
        apply([.paragraphStyle: tableParagraphStyle], to: result)
        return result
    }

    private func textAlignment(for alignment: Table.ColumnAlignment?) -> NSTextAlignment {
        switch alignment {
        case .left, nil:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        }
    }

    private mutating func renderTableRow(
        _ cells: [Table.Cell],
        columnCount: Int,
        alignments: [NSTextAlignment],
        isHeader: Bool
    ) -> [ChatMarkdownTableCell] {
        (0..<columnCount).map { column in
            guard column < cells.count else {
                return ChatMarkdownTableCell(
                    attributedText: NSAttributedString(string: "", attributes: bodyAttributes()),
                    alignment: alignments[safe: column] ?? .left,
                    isHeader: isHeader
                )
            }

            return renderTableCell(
                cells[column],
                isHeader: isHeader,
                alignment: alignments[safe: column] ?? .left
            )
        }
    }

    private mutating func renderTableCell(
        _ cell: Table.Cell,
        isHeader: Bool,
        alignment: NSTextAlignment
    ) -> ChatMarkdownTableCell {
        let result = renderInlineChildren(of: cell)
        trimTrailingNewlines(in: result)
        replaceNewlinesWithSpaces(in: result)
        applyTableCellParagraphStyle(to: result, alignment: alignment)

        if isHeader {
            applyTableHeaderFont(to: result)
        }

        return ChatMarkdownTableCell(
            attributedText: result,
            alignment: alignment,
            isHeader: isHeader
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

    private func applyTableCellParagraphStyle(
        to attributedString: NSMutableAttributedString,
        alignment: NSTextAlignment
    ) {
        transformParagraphStyles(in: attributedString) { paragraphStyle in
            paragraphStyle.alignment = alignment
            paragraphStyle.lineBreakMode = .byCharWrapping
            paragraphStyle.lineSpacing = 1.0
            paragraphStyle.paragraphSpacing = 0.0
        }
    }

    private func applyTableHeaderFont(to attributedString: NSMutableAttributedString) {
        guard attributedString.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let font = (value as? UIFont) ?? currentBodyFont()
            attributedString.addAttribute(.font, value: font.withTableBoldTrait(), range: range)
        }
    }

    private var tableParagraphStyle: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0.0
        paragraphStyle.paragraphSpacingBefore = 4.0
        paragraphStyle.paragraphSpacing = ChatMarkdownTableLayoutMetrics.paragraphSpacing
        return paragraphStyle
    }
}

struct ChatMarkdownTableData {
    var rows: [[ChatMarkdownTableCell]]
    var columnCount: Int

    var isEmpty: Bool {
        rows.isEmpty || columnCount == 0
    }
}

struct ChatMarkdownTableCell {
    var attributedText: NSAttributedString
    var alignment: NSTextAlignment
    var isHeader: Bool

    var accessibilityText: String {
        attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChatMarkdownTableLayout {
    var columnWidths: [CGFloat]
    var rowHeights: [CGFloat]
    var contentSize: CGSize
}

extension ChatMarkdownTableLayout {
    static func makeLayout(for tableData: ChatMarkdownTableData) -> ChatMarkdownTableLayout {
        let columnWidths = preferredColumnWidths(for: tableData)
        let rowHeights = tableData.rows.map { row in
            rowHeight(for: row, columnWidths: columnWidths, columnCount: tableData.columnCount)
        }
        let tableHeight = rowHeights.reduce(0.0, +)
        let tableWidth = columnWidths.reduce(0.0, +)

        return ChatMarkdownTableLayout(
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            contentSize: CGSize(
                width: ceil(tableWidth),
                height: ceil(tableHeight + ChatMarkdownTableLayoutMetrics.verticalMargin * 2.0)
            )
        )
    }

    private static func preferredColumnWidths(for tableData: ChatMarkdownTableData) -> [CGFloat] {
        (0..<tableData.columnCount).map { column in
            let preferredWidth = tableData.rows.reduce(ChatMarkdownTableLayoutMetrics.minColumnWidth) { current, row in
                guard let cell = row[safe: column] else {
                    return current
                }

                let measured = ceil(
                    cell.attributedText.boundingRect(
                        with: CGSize(
                            width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude
                        ),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    ).width
                )
                return max(current, measured + ChatMarkdownTableLayoutMetrics.cellHorizontalPadding * 2.0)
            }

            return min(
                max(preferredWidth, ChatMarkdownTableLayoutMetrics.minColumnWidth),
                ChatMarkdownTableLayoutMetrics.maxColumnWidth
            )
        }
    }

    private static func rowHeight(
        for row: [ChatMarkdownTableCell],
        columnWidths: [CGFloat],
        columnCount: Int
    ) -> CGFloat {
        var rowHeight = ChatMarkdownTableLayoutMetrics.minRowHeight
        for column in 0..<columnCount {
            guard let cell = row[safe: column],
                  let columnWidth = columnWidths[safe: column] else {
                continue
            }

            let textWidth = max(1.0, columnWidth - ChatMarkdownTableLayoutMetrics.cellHorizontalPadding * 2.0)
            let textHeight = measuredTextHeight(cell.attributedText, width: textWidth)
            rowHeight = max(rowHeight, textHeight + ChatMarkdownTableLayoutMetrics.cellVerticalPadding * 2.0)
        }

        return ceil(rowHeight)
    }

    private static func measuredTextHeight(_ attributedText: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attributedText.length > 0 else {
            return 0.0
        }

        return ceil(
            attributedText.boundingRect(
                with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}

private extension UIFont {
    func withTableBoldTrait() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitBold)) else {
            return .boldSystemFont(ofSize: pointSize)
        }

        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
