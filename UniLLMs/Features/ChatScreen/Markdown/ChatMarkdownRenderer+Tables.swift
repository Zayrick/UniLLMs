//
//  ChatMarkdownRenderer+Tables.swift
//  UniLLMs
//
//  Table Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

extension ChatMarkdownRenderer {
    mutating func renderTable(_ table: Table) -> NSMutableAttributedString {
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
                let divider = "| " + widths.map {
                    String(repeating: "-", count: max(3, $0))
                }.joined(separator: " | ") + " |"
                return line + "\n" + divider
            }
            return line
        }.joined(separator: "\n") + "\n"

        return blockString(
            text,
            attributes: [
                .font: style.codeFont(compatibleWith: traitCollection),
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
}
