//
//  ChatMarkdownInlineCodeStyle.swift
//  UniLLMs
//
//  Inline code styling values for chat Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

enum ChatMarkdownInlineCodeStyle {
    static let outerMargin = " "
    static let horizontalPadding: CGFloat = 3.0
    static let interLineGap: CGFloat = 1.0
    static let cornerRadius: CGFloat = 5.0
}

extension NSAttributedString.Key {
    static let chatInlineCodeBackgroundColor = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.inlineCodeBackgroundColor"
    )
    static let chatInlineCodeCornerRadius = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.inlineCodeCornerRadius"
    )
}
