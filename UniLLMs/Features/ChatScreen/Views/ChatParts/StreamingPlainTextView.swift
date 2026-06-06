//
//  StreamingPlainTextView.swift
//  UniLLMs
//
//  Displays streamed assistant text without parsing or transforming markup.
//  Created by Codex on 2026/6/6.
//

import UIKit

final class StreamingPlainTextView: UITextView {
    enum Style {
        case rawText
        case thinking

        var textStyle: UIFont.TextStyle {
            switch self {
            case .rawText:
                return .body
            case .thinking:
                return .callout
            }
        }

        var textColor: UIColor {
            switch self {
            case .rawText:
                return .label
            case .thinking:
                return .secondaryLabel
            }
        }
    }

    var onNeedsHeightUpdate: (() -> Void)?

    private let style: Style
    private var bufferedText = ""

    init(style: Style = .rawText) {
        self.style = style
        super.init(frame: .zero, textContainer: nil)
        configure()
    }

    required init?(coder: NSCoder) {
        style = .rawText
        super.init(coder: coder)
        configure()
    }

    func appendText(_ textDelta: String) {
        guard !textDelta.isEmpty else {
            return
        }

        bufferedText += textDelta
        text = bufferedText
        notifyHeightChanged()
    }

    func setFinishedText(_ text: String) {
        bufferedText = text
        self.text = text
        notifyHeightChanged()
    }

    func finishStreamingContent() {
        notifyHeightChanged()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        dataDetectorTypes = []
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0.0
        textContainer.lineBreakMode = .byWordWrapping
        font = .preferredFont(forTextStyle: style.textStyle)
        adjustsFontForContentSizeCategory = true
        textColor = style.textColor
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
    }

    private func notifyHeightChanged() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onNeedsHeightUpdate?()
    }
}
