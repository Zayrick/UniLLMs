//
//  StreamingMarkdownView.swift
//  UniLLMs
//
//  UIView that renders accumulated streamed Markdown as presentation blocks.
//  Created by Zayrick on 2026/5/12.
//

import UIKit

final class StreamingMarkdownView: UIView {
    private let stackView = UIStackView()
    private var segmenter = ChatMarkdownStreamSegmenter()
    private var completedSegmentMarkdown: [String] = []
    private var currentSegmentMarkdown: String?
    private var currentSegmentViews: [UIView] = []
    private var traitChangeRegistration: (any UITraitChangeRegistration)?
    var onNeedsHeightUpdate: (() -> Void)?

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

        applyStreamUpdate(segmenter.append(string))
    }

    func finishStreamingContent() {
        applyStreamUpdate(segmenter.finish())
    }

    func resetMarkdown() {
        segmenter.reset()
        completedSegmentMarkdown = []
        currentSegmentMarkdown = nil
        currentSegmentViews = []
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
            view.renderAllSegments()
        }
    }

    private func applyStreamUpdate(_ update: ChatMarkdownStreamUpdate) {
        removeCurrentSegmentViews()

        for segment in update.completedSegments {
            completedSegmentMarkdown.append(segment)
            addRenderedSegment(segment)
        }

        currentSegmentMarkdown = update.currentSegment
        if let currentSegment = update.currentSegment {
            currentSegmentViews = addRenderedSegment(currentSegment)
        }

        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    private func renderAllSegments() {
        removeRenderedBlocks()

        for segment in completedSegmentMarkdown {
            addRenderedSegment(segment)
        }

        if let currentSegment = currentSegmentMarkdown {
            currentSegmentViews = addRenderedSegment(currentSegment)
        }

        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    @discardableResult
    private func addRenderedSegment(_ markdown: String) -> [UIView] {
        let renderer = ChatMarkdownRenderer(traitCollection: traitCollection)
        let blocks = renderer.render(markdown: markdown)
        var views: [UIView] = []

        for block in blocks {
            switch block {
            case let .text(attributedText):
                guard attributedText.length > 0 else {
                    continue
                }
                let textView = ChatMarkdownTextView(attributedText: attributedText)
                stackView.addArrangedSubview(textView)
                views.append(textView)
            case let .codeBlock(codeBlock):
                let codeBlockView = ChatMarkdownCodeBlockView(
                    codeBlock: codeBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                stackView.addArrangedSubview(codeBlockView)
                views.append(codeBlockView)
            case let .table(tableData):
                let tableView = ChatMarkdownTableView(
                    tableData: tableData,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                stackView.addArrangedSubview(tableView)
                views.append(tableView)
            case let .image(imageBlock):
                let imageView = ChatMarkdownImageView(
                    imageBlock: imageBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                imageView.onImageSizeDidChange = { [weak self] in
                    self?.handleRenderedImageSizeChange()
                }
                stackView.addArrangedSubview(imageView)
                views.append(imageView)
            }
        }

        return views
    }

    private func removeRenderedBlocks() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        currentSegmentViews = []
        invalidateIntrinsicContentSize()
    }

    private func removeCurrentSegmentViews() {
        for view in currentSegmentViews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        currentSegmentViews = []
    }

    private func handleRenderedImageSizeChange() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onNeedsHeightUpdate?()
    }

    private func fittingHeight(for width: CGFloat) -> CGFloat {
        let fittingWidth = max(1.0, width)
        return stackView.arrangedSubviews.reduce(0.0) { height, view in
            let fittingSize = view.systemLayoutSizeFitting(
                CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            return height + ceil(fittingSize.height)
        }
    }
}
