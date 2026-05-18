//
//  StreamingMarkdownView.swift
//  UniLLMs
//
//  UIView that renders accumulated streamed Markdown as presentation blocks.
//  Ingestion is decoupled from rendering: `appendMarkdown` only writes to a
//  pending buffer in O(1); a CADisplayLink drains the buffer at most once per
//  screen refresh and adapts (skips frames) when a render exceeds the frame
//  budget, providing natural backpressure on fast token streams.
//
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

    private var pendingMarkdown = ""
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var framesToSkip: Int = 0
    private var lastRenderDuration: CFTimeInterval = 0
    private var isStreaming = false

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

    deinit {
        displayLink?.invalidate()
    }

    func appendMarkdown(_ string: String) {
        guard !string.isEmpty else {
            return
        }

        pendingMarkdown.append(string)
        isStreaming = true
        startDisplayLinkIfNeeded()
    }

    func setFinishedMarkdown(_ markdown: String) {
        stopDisplayLink()
        pendingMarkdown = ""
        isStreaming = false
        segmenter.reset()
        completedSegmentMarkdown = markdown.isEmpty ? [] : [markdown]
        currentSegmentMarkdown = nil
        currentSegmentViews = []
        removeRenderedBlocks()

        if !markdown.isEmpty {
            addRenderedSegment(markdown)
        }

        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    func finishStreamingContent() {
        isStreaming = false
        stopDisplayLink()
        flushPendingMarkdown()
        applyStreamUpdate(segmenter.finish())
    }

    func resetMarkdown() {
        stopDisplayLink()
        pendingMarkdown = ""
        isStreaming = false
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
        stackView.spacing = UIStackView.spacingUseSystem
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

    // MARK: - Frame-driven scheduling

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy(target: self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLinkProxy = proxy
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        framesToSkip = 0
    }

    fileprivate func handleDisplayLinkTick() {
        if framesToSkip > 0 {
            framesToSkip -= 1
            return
        }

        flushPendingMarkdown()

        if pendingMarkdown.isEmpty && !isStreaming {
            stopDisplayLink()
        } else if pendingMarkdown.isEmpty {
            // Streaming still active but caught up — pause the link to save CPU.
            // It restarts on the next appendMarkdown.
            stopDisplayLink()
        }
    }

    private func flushPendingMarkdown() {
        guard !pendingMarkdown.isEmpty else { return }
        let chunk = pendingMarkdown
        pendingMarkdown = ""

        let start = CACurrentMediaTime()
        applyStreamUpdate(segmenter.append(chunk))
        lastRenderDuration = CACurrentMediaTime() - start

        // Adaptive backoff: if the render exceeded the frame budget, skip
        // proportionally many frames so the runloop has room to breathe.
        let frameBudget: CFTimeInterval = 1.0 / 60.0
        if lastRenderDuration > frameBudget {
            framesToSkip = min(Int(lastRenderDuration / frameBudget), 6)
        } else {
            framesToSkip = 0
        }
    }

    // MARK: - Rendering

    private func applyStreamUpdate(_ update: ChatMarkdownStreamUpdate) {
        for segment in update.completedSegments {
            if !currentSegmentViews.isEmpty {
                removeCurrentSegmentViews()
            }
            completedSegmentMarkdown.append(segment)
            addRenderedSegment(segment)
        }

        currentSegmentMarkdown = update.currentSegment
        if let currentSegment = update.currentSegment {
            let renderer = ChatMarkdownRenderer(traitCollection: traitCollection)
            let blocks = renderer.render(markdown: currentSegment)

            if currentSegmentViews.count == blocks.count {
                var canUpdateInPlace = true
                for i in 0..<blocks.count {
                    if case .text = blocks[i], currentSegmentViews[i] is ChatMarkdownTextView {
                        continue
                    } else {
                        canUpdateInPlace = false
                        break
                    }
                }

                if canUpdateInPlace {
                    for i in 0..<blocks.count {
                        if case let .text(attributedText) = blocks[i],
                           let textView = currentSegmentViews[i] as? ChatMarkdownTextView {
                            textView.updateMarkdownAttributedTextWithBlur(attributedText)
                        }
                    }
                    invalidateIntrinsicContentSize()
                    onNeedsHeightUpdate?()
                    return
                }
            }

            removeCurrentSegmentViews()
            currentSegmentViews = addRenderedSegment(currentSegment)
        } else {
            removeCurrentSegmentViews()
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
            case let .mathBlock(mathBlock):
                let mathBlockView = ChatMarkdownMathBlockView(
                    mathBlock: mathBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                stackView.addArrangedSubview(mathBlockView)
                views.append(mathBlockView)
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
            case let .details(detailsBlock):
                let detailsView = ChatMarkdownDetailsView(
                    detailsBlock: detailsBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                detailsView.onNeedsHeightUpdate = { [weak self] in
                    self?.handleRenderedImageSizeChange()
                }
                stackView.addArrangedSubview(detailsView)
                views.append(detailsView)
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
        return ceil(
            stackView.systemLayoutSizeFitting(
                CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        )
    }
}

private final class DisplayLinkProxy {
    weak var target: StreamingMarkdownView?

    init(target: StreamingMarkdownView) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        target?.handleDisplayLinkTick()
    }
}
