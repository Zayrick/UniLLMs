//
//  StreamingMarkdownTextView.swift
//  UniLLMs
//
//  UITextView subclass that renders accumulated streamed Markdown text.
//  Created by Codex on 2026/5/12.
//

import UIKit

final class StreamingMarkdownTextView: UITextView {
    private var markdownText = ""

    func appendMarkdown(_ string: String) {
        guard !string.isEmpty else {
            return
        }

        markdownText += string
        renderMarkdown()
    }

    func finishStreamingContent() {
        renderMarkdown()
    }

    func resetMarkdown() {
        markdownText = ""
        attributedText = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        renderMarkdown()
    }

    private func renderMarkdown() {
        guard !markdownText.isEmpty else {
            attributedText = nil
            return
        }

        var renderer = ChatMarkdownRenderer()
        attributedText = renderer.render(markdown: markdownText)
        invalidateIntrinsicContentSize()
    }
}
