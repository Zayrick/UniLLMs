//
//  StreamingMarkdownView.swift
//  UniLLMs
//
//  UIView that renders accumulated streamed Markdown as text and table blocks.
//  Created by Zayrick on 2026/5/12.
//

import UIKit

final class StreamingMarkdownView: UIView {
    private let stackView = UIStackView()
    private var markdownText = ""
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        configureTraitObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
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
        removeRenderedBlocks()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: max(1.0, size.width), height: fittingHeight(for: size.width))
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 0.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [
                UITraitUserInterfaceStyle.self,
                UITraitPreferredContentSizeCategory.self,
                UITraitDisplayScale.self
            ]
        ) { (view: StreamingMarkdownView, _) in
            view.renderMarkdown()
        }
    }

    private func renderMarkdown() {
        guard !markdownText.isEmpty else {
            removeRenderedBlocks()
            return
        }

        var renderer = ChatMarkdownRenderer(traitCollection: traitCollection)
        let blocks = renderer.renderBlocks(markdown: markdownText)

        removeRenderedBlocks()
        for block in blocks {
            switch block {
            case let .text(attributedText):
                guard attributedText.length > 0 else {
                    continue
                }
                stackView.addArrangedSubview(ChatMarkdownTextBlockView(attributedText: attributedText))
            case let .table(tableData):
                stackView.addArrangedSubview(
                    ChatMarkdownTableView(
                        tableData: tableData,
                        style: renderer.style,
                        traitCollection: traitCollection
                    )
                )
            }
        }

        invalidateIntrinsicContentSize()
    }

    private func removeRenderedBlocks() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        invalidateIntrinsicContentSize()
    }

    private func fittingHeight(for width: CGFloat) -> CGFloat {
        let fittingWidth = max(1.0, width)
        return stackView.arrangedSubviews.reduce(0.0) { height, view in
            let fittingSize = view.sizeThatFits(
                CGSize(width: fittingWidth, height: CGFloat.greatestFiniteMagnitude)
            )
            return height + ceil(fittingSize.height)
        }
    }
}

private final class ChatMarkdownTextBlockView: UITextView {
    init(attributedText: NSAttributedString) {
        super.init(frame: .zero, textContainer: nil)
        configure()
        self.attributedText = attributedText
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        isSelectable = false
        isUserInteractionEnabled = true
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0.0
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
        translatesAutoresizingMaskIntoConstraints = false
    }
}
