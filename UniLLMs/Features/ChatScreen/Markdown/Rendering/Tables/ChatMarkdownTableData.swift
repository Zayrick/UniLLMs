//
//  ChatMarkdownTableData.swift
//  UniLLMs
//
//  Rendered Markdown table data shared by renderer and presentation views.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

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
