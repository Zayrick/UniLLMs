//
//  ChatMarkdownBlockQuoteStyle.swift
//  UniLLMs
//
//  Block quote styling values for chat Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

enum ChatMarkdownBlockQuoteStyle {
    static let indentPerLevel: CGFloat = 12.0
    static let barWidth: CGFloat = 3.0
    static let barLeading: CGFloat = 2.0

    static var barColor: UIColor {
        UIColor.tertiaryLabel
    }
}

extension NSAttributedString.Key {
    static let chatBlockQuoteBarPositions = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.blockQuoteBarPositions"
    )
}
