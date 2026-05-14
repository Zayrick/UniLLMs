//
//  ChatMarkdownTableRenderer.swift
//  UniLLMs
//
//  Table Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

final class ChatMarkdownTableRenderer {
    private let context: ChatMarkdownRenderingContext
    private let inlineRenderer: ChatMarkdownInlineRenderer

    init(
        context: ChatMarkdownRenderingContext,
        inlineRenderer: ChatMarkdownInlineRenderer
    ) {
        self.context = context
        self.inlineRenderer = inlineRenderer
    }

    func renderPlainText(_ table: Table) -> NSMutableAttributedString {
        let tableData = renderData(table)
        guard !tableData.isEmpty else {
            return NSMutableAttributedString()
        }

        return renderPlainText(tableData)
    }

    func renderData(_ table: Table) -> ChatMarkdownTableData {
        let headerCells = Array(table.head.cells)
        let bodyRows = table.body.rows.map { Array($0.cells) }
        let bodyColumnCount = bodyRows.map(\.count).max() ?? 0
        let columnCount = max(max(headerCells.count, bodyColumnCount), table.columnAlignments.count)

        guard columnCount > 0 else {
            return ChatMarkdownTableData(rows: [], columnCount: 0)
        }

        let alignments = (0..<columnCount).map { column in
            textAlignment(for: table.columnAlignments[chatMarkdownSafe: column].flatMap { $0 })
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

    private func renderPlainText(_ tableData: ChatMarkdownTableData) -> NSMutableAttributedString {
        let text = tableData.rows
            .map { row in
                row.map(\.accessibilityText).joined(separator: "  ")
            }
            .joined(separator: "\n")
        let result = NSMutableAttributedString(string: text + "\n", attributes: context.bodyAttributes())
        context.apply([.paragraphStyle: tableParagraphStyle], to: result)
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

    private func renderTableRow(
        _ cells: [Table.Cell],
        columnCount: Int,
        alignments: [NSTextAlignment],
        isHeader: Bool
    ) -> [ChatMarkdownTableCell] {
        (0..<columnCount).map { column in
            guard column < cells.count else {
                return ChatMarkdownTableCell(
                    attributedText: NSAttributedString(string: "", attributes: context.bodyAttributes()),
                    alignment: alignments[chatMarkdownSafe: column] ?? .left,
                    isHeader: isHeader
                )
            }

            return renderTableCell(
                cells[column],
                isHeader: isHeader,
                alignment: alignments[chatMarkdownSafe: column] ?? .left
            )
        }
    }

    private func renderTableCell(
        _ cell: Table.Cell,
        isHeader: Bool,
        alignment: NSTextAlignment
    ) -> ChatMarkdownTableCell {
        let result = inlineRenderer.renderChildren(of: cell)
        context.trimTrailingNewlines(in: result)
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
        context.transformParagraphStyles(in: attributedString) { paragraphStyle in
            paragraphStyle.alignment = alignment
            paragraphStyle.lineBreakMode = .byCharWrapping
            paragraphStyle.lineSpacing = context.style.compactLineSpacing(compatibleWith: context.traitCollection)
            paragraphStyle.paragraphSpacing = 0.0
        }
    }

    private func applyTableHeaderFont(to attributedString: NSMutableAttributedString) {
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

    private var tableParagraphStyle: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = context.style.compactLineSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacingBefore = context.style.bodyParagraphSpacing(compatibleWith: context.traitCollection)
        paragraphStyle.paragraphSpacing = context.style.bodyParagraphSpacing(compatibleWith: context.traitCollection)
        return paragraphStyle
    }
}
