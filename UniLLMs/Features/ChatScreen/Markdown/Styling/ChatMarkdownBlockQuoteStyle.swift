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

    nonisolated static func barPositions(forDepth depth: Int) -> [CGFloat] {
        guard depth > 0 else {
            return []
        }

        return (0..<depth).map { level in
            barLeading + CGFloat(level) * indentPerLevel
        }
    }

    nonisolated static func addingBarPosition(
        _ position: CGFloat,
        to existingPositions: [CGFloat]
    ) -> [CGFloat] {
        var result = existingPositions
        if !result.contains(position) {
            result.append(position)
        }
        return result.sorted()
    }

    nonisolated static func shiftingBarPositions(
        _ positions: [CGFloat],
        by offset: CGFloat
    ) -> [CGFloat] {
        positions.map { $0 + offset }
    }

    nonisolated static var barColor: UIColor {
        UIColor.tertiaryLabel
    }
}

extension NSAttributedString.Key {
    nonisolated static let chatBlockQuoteBarPositions = NSAttributedString.Key(
        "UniLLMs.ChatMarkdown.blockQuoteBarPositions"
    )
}
