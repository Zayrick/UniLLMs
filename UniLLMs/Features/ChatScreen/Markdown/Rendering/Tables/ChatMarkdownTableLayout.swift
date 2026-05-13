//
//  ChatMarkdownTableLayout.swift
//  UniLLMs
//
//  Layout measurements for rendered Markdown tables.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

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
                guard let cell = row[chatMarkdownSafe: column] else {
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
            guard let cell = row[chatMarkdownSafe: column],
                  let columnWidth = columnWidths[chatMarkdownSafe: column] else {
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

extension Array {
    subscript(chatMarkdownSafe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
