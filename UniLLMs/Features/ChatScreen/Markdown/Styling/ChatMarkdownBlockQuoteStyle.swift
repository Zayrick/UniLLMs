//
//  ChatMarkdownBlockQuoteStyle.swift
//  UniLLMs
//
//  Block quote styling values for chat Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

enum ChatMarkdownBlockQuoteStyle {
    nonisolated static let indentPerLevel: CGFloat = 12.0
    nonisolated static let barWidth: CGFloat = 3.0
    nonisolated static let barLeading: CGFloat = 2.0

    nonisolated static var barColor: UIColor {
        UIColor.tertiaryLabel
    }
}

extension NSAttributedString.Key {
    nonisolated static let chatBlockQuoteBarPositions = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.blockQuoteBarPositions"
    )
}
