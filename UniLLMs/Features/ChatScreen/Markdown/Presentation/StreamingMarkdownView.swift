//
//  StreamingMarkdownView.swift
//  UniLLMs
//
//  UIView that renders accumulated streamed Markdown as presentation blocks.
//  Streaming owns only buffering, frame pacing, and view reuse. Markdown
//  semantics stay in ChatMarkdownStreamSegmenter and ChatMarkdownRenderer.
//
//  Created by Zayrick on 2026/5/12.
//

import UIKit

final class StreamingMarkdownView: UIView {
    private enum Scheduling {
        static let maxCharactersPerFlush = 4096
    }

    private let style: ChatMarkdownRenderStyle
    private let imageLoader: any ChatMarkdownImageLoading
    private let stackView = UIStackView()
    private var segmenter = ChatMarkdownStreamSegmenter()
    private var presentationTimeline = ChatStreamingMarkdownPresentationTimeline<ChatMarkdownRenderedBlockViewRecord>()
    private var traitChangeRegistration: (any UITraitChangeRegistration)?
    private var isRenderAllSegmentsScheduled = false
    var onNeedsHeightUpdate: (() -> Void)?

    private var pendingMarkdownBuffer = ChatMarkdownPendingBuffer()
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var framesToSkip: Int = 0

    init(
        style: ChatMarkdownRenderStyle = .assistant,
        imageLoader: any ChatMarkdownImageLoading = URLSessionChatMarkdownImageLoader()
    ) {
        self.style = style
        self.imageLoader = imageLoader
        super.init(frame: .zero)
        configure()
        configureTraitObservation()
    }

    override init(frame: CGRect) {
        style = .assistant
        imageLoader = URLSessionChatMarkdownImageLoader()
        super.init(frame: frame)
        configure()
        configureTraitObservation()
    }

    required init?(coder: NSCoder) {
        style = .assistant
        imageLoader = URLSessionChatMarkdownImageLoader()
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

        pendingMarkdownBuffer.append(string)
        startDisplayLinkIfNeeded()
    }

    func setFinishedMarkdown(_ markdown: String) {
        stopDisplayLink()
        pendingMarkdownBuffer.clear()
        resetRenderedState()
        segmenter.reset()
        presentationTimeline.setFinishedMarkdown(markdown) { [weak self] segment in
            self?.appendRenderedSegment(segment, animation: .none) ?? []
        }

        notifyHeightChanged()
    }

    func finishStreamingContent() {
        stopDisplayLink()
        flushPendingMarkdown(limitToFrameBudget: false, notify: false)
        applyStreamUpdate(segmenter.finish(), notify: true)
    }

    func resetMarkdown() {
        stopDisplayLink()
        pendingMarkdownBuffer.clear()
        segmenter.reset()
        presentationTimeline.reset()
        resetRenderedState()
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
            view.scheduleRenderAllSegments()
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

        flushPendingMarkdown(limitToFrameBudget: true, notify: true)

        if !pendingMarkdownBuffer.hasPendingMarkdown {
            stopDisplayLink()
        }
    }

    private func flushPendingMarkdown(limitToFrameBudget: Bool, notify: Bool) {
        guard pendingMarkdownBuffer.hasPendingMarkdown else { return }
        let chunk = limitToFrameBudget
            ? pendingMarkdownBuffer.nextChunk(maxCharacters: Scheduling.maxCharactersPerFlush)
            : pendingMarkdownBuffer.drain()

        let start = CACurrentMediaTime()
        applyStreamUpdate(segmenter.append(chunk), notify: notify)
        let renderDuration = CACurrentMediaTime() - start

        let frameBudget: CFTimeInterval = 1.0 / 60.0
        if renderDuration > frameBudget {
            framesToSkip = min(Int(renderDuration / frameBudget), 6)
        } else {
            framesToSkip = 0
        }
    }

    // MARK: - Rendering

    private func applyStreamUpdate(_ update: ChatMarkdownStreamUpdate, notify: Bool) {
        presentationTimeline.applyStreamUpdate(
            update,
            commitCurrentSegment: { [weak self] markdown, records in
                self?.commitCurrentSegment(markdown: markdown, records: records) ?? false
            },
            appendCompletedSegment: { [weak self] markdown in
                self?.appendRenderedSegment(markdown, animation: .streaming) ?? []
            },
            removeCurrentRecords: { [weak self] records in
                self?.removeRecords(records)
            },
            renderCurrentSegment: { [weak self] markdown, records in
                self?.renderCurrentSegment(markdown: markdown, records: records) ?? []
            }
        )

        if notify {
            notifyHeightChanged()
        }
    }

    private func commitCurrentSegment(
        markdown: String,
        records: [ChatMarkdownRenderedBlockViewRecord]
    ) -> Bool {
        guard !records.isEmpty else {
            return false
        }

        let renderer = makeRenderer()
        let blocks = renderer.render(markdown: markdown)
        guard ChatMarkdownRenderedBlockViewReconciler.updateAllInPlaceIfPossible(
            records,
            with: blocks,
            allowsIdentityChange: true,
            animation: .streaming
        ) else {
            return false
        }

        return true
    }

    private func renderAllSegments() {
        presentationTimeline.removeCurrentRecords { [weak self] records in
            self?.removeRecords(records)
        }
        let renderer = makeRenderer()
        let configuration = blockViewConfiguration(for: renderer)

        presentationTimeline.rerenderCompletedSegments { segment, records, startIndex in
            let blocks = renderer.render(markdown: segment)
            return ChatMarkdownRenderedBlockViewReconciler.reconcile(
                blocks,
                records: records,
                in: stackView,
                startingAt: startIndex,
                configuration: configuration
            )
        }

        if let currentSegmentMarkdown = presentationTimeline.currentSegmentMarkdown {
            let records = renderCurrentSegment(
                markdown: currentSegmentMarkdown,
                records: presentationTimeline.currentRecords
            )
            presentationTimeline.updateCurrentSegment(
                markdown: currentSegmentMarkdown,
                records: records
            )
        }

        notifyHeightChanged()
    }

    @discardableResult
    private func appendRenderedSegment(
        _ markdown: String,
        animation: ChatMarkdownRenderedBlockViewAnimation
    ) -> [ChatMarkdownRenderedBlockViewRecord] {
        let renderer = makeRenderer()
        return ChatMarkdownRenderedBlockViewReconciler.append(
            renderer.render(markdown: markdown),
            to: stackView,
            configuration: blockViewConfiguration(for: renderer, animation: animation)
        )
    }

    private func renderCurrentSegment(
        markdown: String,
        records currentRecords: [ChatMarkdownRenderedBlockViewRecord]
    ) -> [ChatMarkdownRenderedBlockViewRecord] {
        let renderer = makeRenderer()
        let plan = ChatMarkdownCurrentSegmentRenderPlan(blocks: renderer.render(markdown: markdown))
        let startIndex = max(0, stackView.arrangedSubviews.count - currentRecords.count)
        return ChatMarkdownRenderedBlockViewReconciler.reconcile(
            plan.blocks,
            records: currentRecords,
            in: stackView,
            startingAt: startIndex,
            allowsIdentityChange: true,
            configuration: blockViewConfiguration(for: renderer, animation: .streaming)
        )
    }

    private func makeRenderer() -> ChatMarkdownRenderer {
        ChatMarkdownRenderer(style: style, traitCollection: traitCollection)
    }

    private func blockViewConfiguration(
        for renderer: ChatMarkdownRenderer,
        animation: ChatMarkdownRenderedBlockViewAnimation = .none
    ) -> ChatMarkdownRenderedBlockViewConfiguration {
        ChatMarkdownRenderedBlockViewConfiguration(
            style: renderer.style,
            traitCollection: traitCollection,
            animation: animation,
            imageLoader: imageLoader
        ) { [weak self] in
            self?.notifyHeightChanged()
        }
    }

    private func resetRenderedState() {
        ChatMarkdownRenderedBlockViewReconciler.removeAllArrangedSubviews(in: stackView)
        invalidateIntrinsicContentSize()
    }

    private func removeRecords(_ records: [ChatMarkdownRenderedBlockViewRecord]) {
        ChatMarkdownRenderedBlockViewReconciler.remove(records, from: stackView)
    }

    private func notifyHeightChanged() {
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

    private func scheduleRenderAllSegments() {
        guard !isRenderAllSegmentsScheduled else {
            return
        }

        isRenderAllSegmentsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            isRenderAllSegmentsScheduled = false
            renderAllSegments()
        }
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
