//
//  ChatMarkdownRenderingContext.swift
//  UniLLMs
//
//  Shared state and style context for chat Markdown renderers.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

final class ChatMarkdownRenderingContext {
    let style: ChatMarkdownRenderStyle
    let traitCollection: UITraitCollection
    private var listDepthValue = 0
    private var orderedListCounters: [Int] = []
    private let footnotes: [String: ChatMarkdownFootnoteDefinition]
    private var footnoteDisplayNumbers: [String: Int] = [:]
    private var nextFootnoteDisplayNumber = 1

    init(
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection,
        footnotes: [String: ChatMarkdownFootnoteDefinition] = [:]
    ) {
        self.style = style
        self.traitCollection = traitCollection
        self.footnotes = footnotes
    }

    var listDepth: Int {
        listDepthValue
    }

    func pushUnorderedList() {
        listDepthValue += 1
    }

    func popUnorderedList() {
        popList()
    }

    func pushOrderedList(startIndex: Int) {
        listDepthValue += 1
        orderedListCounters.append(startIndex)
    }

    func popOrderedList() {
        if !orderedListCounters.isEmpty {
            orderedListCounters.removeLast()
        }
        popList()
    }

    func advanceOrderedListCounter() -> Int {
        let current = orderedListCounters.last ?? 1
        if !orderedListCounters.isEmpty {
            orderedListCounters[orderedListCounters.count - 1] = current + 1
        }
        return current
    }

    func footnotePresentation(forLabel label: String) -> ChatMarkdownFootnotePresentation? {
        let normalizedLabel = ChatMarkdownFootnoteLabel.normalized(label)
        guard let footnote = footnotes[normalizedLabel] else {
            return nil
        }

        let displayNumber: Int
        if let existingDisplayNumber = footnoteDisplayNumbers[normalizedLabel] {
            displayNumber = existingDisplayNumber
        } else {
            displayNumber = nextFootnoteDisplayNumber
            footnoteDisplayNumbers[normalizedLabel] = displayNumber
            nextFootnoteDisplayNumber += 1
        }

        return ChatMarkdownFootnotePresentation(
            label: footnote.label,
            displayText: "\(displayNumber)",
            content: footnote.content
        )
    }

    private func popList() {
        listDepthValue = max(0, listDepthValue - 1)
    }
}
