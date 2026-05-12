//
//  StreamingMarkdownTextView.swift
//  UniLLMs
//
//  UITextView subclass that renders accumulated streamed Markdown text.
//  Created by Zayrick on 2026/5/12.
//

import UIKit

final class StreamingMarkdownTextView: UITextView {
    private var markdownText = ""
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureTraitObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTraitObservation()
    }

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

    private func configureTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [
                UITraitUserInterfaceStyle.self,
                UITraitPreferredContentSizeCategory.self,
                UITraitDisplayScale.self
            ]
        ) { (textView: StreamingMarkdownTextView, _) in
            textView.renderMarkdown()
        }
    }

    private func renderMarkdown() {
        guard !markdownText.isEmpty else {
            attributedText = nil
            return
        }

        var renderer = ChatMarkdownRenderer(traitCollection: traitCollection)
        attributedText = renderer.render(markdown: markdownText)
        invalidateIntrinsicContentSize()
    }
}
