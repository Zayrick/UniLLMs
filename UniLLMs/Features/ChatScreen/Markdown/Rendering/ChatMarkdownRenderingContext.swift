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

    init(style: ChatMarkdownRenderStyle, traitCollection: UITraitCollection) {
        self.style = style
        self.traitCollection = traitCollection
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

    private func popList() {
        listDepthValue = max(0, listDepthValue - 1)
    }
}
