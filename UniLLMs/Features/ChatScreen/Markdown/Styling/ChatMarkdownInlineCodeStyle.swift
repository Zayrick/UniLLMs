//
//  ChatMarkdownInlineCodeStyle.swift
//  UniLLMs
//
//  Inline code styling values for chat Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

enum ChatMarkdownInlineCodeStyle {
    nonisolated static let outerMargin = " "
    nonisolated static let horizontalPadding: CGFloat = 3.0
    nonisolated static let interLineGap: CGFloat = 1.0
    nonisolated static let cornerRadius: CGFloat = 5.0
}

extension NSAttributedString.Key {
    nonisolated static let chatInlineCodeBackgroundColor = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.inlineCodeBackgroundColor"
    )
    nonisolated static let chatInlineCodeCornerRadius = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.inlineCodeCornerRadius"
    )
}
