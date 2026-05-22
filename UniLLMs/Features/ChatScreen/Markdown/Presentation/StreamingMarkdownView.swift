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
    private let stackView = UIStackView()
    private var segmenter = ChatMarkdownStreamSegmenter()
    private var completedSegmentMarkdown: [String] = []
    private var completedSegmentRecords: [[ChatMarkdownRenderedBlockViewRecord]] = []
    private var currentSegmentMarkdown: String?
    private var currentSegmentRecords: [ChatMarkdownRenderedBlockViewRecord] = []
    private var traitChangeRegistration: (any UITraitChangeRegistration)?
    private var isRenderAllSegmentsScheduled = false
    var onNeedsHeightUpdate: (() -> Void)?

    private var pendingMarkdownChunks: [String] = []
    private var pendingChunkIndex = 0
    private var pendingChunkStartIndex: String.Index?
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var framesToSkip: Int = 0
    private var lastRenderDuration: CFTimeInterval = 0

    init(style: ChatMarkdownRenderStyle = .assistant) {
        self.style = style
        super.init(frame: .zero)
        configure()
        configureTraitObservation()
    }

    override init(frame: CGRect) {
        style = .assistant
        super.init(frame: frame)
        configure()
        configureTraitObservation()
    }

    required init?(coder: NSCoder) {
        style = .assistant
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

        appendPendingMarkdown(string)
        startDisplayLinkIfNeeded()
    }

    func setFinishedMarkdown(_ markdown: String) {
        stopDisplayLink()
        clearPendingMarkdown()
        resetRenderedState()
        segmenter.reset()
        completedSegmentMarkdown = markdown.isEmpty ? [] : [markdown]
        completedSegmentRecords = []
        currentSegmentMarkdown = nil

        if !markdown.isEmpty {
            completedSegmentRecords.append(appendRenderedSegment(markdown))
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
        clearPendingMarkdown()
        segmenter.reset()
        completedSegmentMarkdown = []
        completedSegmentRecords = []
        currentSegmentMarkdown = nil
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

        if !hasPendingMarkdown {
            stopDisplayLink()
        }
    }

    private func flushPendingMarkdown(limitToFrameBudget: Bool, notify: Bool) {
        guard hasPendingMarkdown else { return }
        let chunk = limitToFrameBudget ? nextPendingChunk() : drainPendingMarkdown()

        let start = CACurrentMediaTime()
        applyStreamUpdate(segmenter.append(chunk), notify: notify)
        lastRenderDuration = CACurrentMediaTime() - start

        let frameBudget: CFTimeInterval = 1.0 / 60.0
        if lastRenderDuration > frameBudget {
            framesToSkip = min(Int(lastRenderDuration / frameBudget), 6)
        } else {
            framesToSkip = 0
        }
    }

    private func nextPendingChunk() -> String {
        var result = ""
        while result.count < Scheduling.maxCharactersPerFlush,
              let currentChunk = pendingCurrentChunk {
            let start = pendingChunkStartIndex ?? currentChunk.startIndex
            let remainingBudget = Scheduling.maxCharactersPerFlush - result.count
            if let end = currentChunk.index(
                start,
                offsetBy: remainingBudget,
                limitedBy: currentChunk.endIndex
            ) {
                result += String(currentChunk[start..<end])
                if end == currentChunk.endIndex {
                    advancePendingChunk()
                } else {
                    pendingChunkStartIndex = end
                }
                break
            }

            result += String(currentChunk[start...])
            advancePendingChunk()
        }

        compactPendingChunksIfNeeded()
        return result
    }

    private func drainPendingMarkdown() -> String {
        var remainingChunks: [String] = []
        while let currentChunk = pendingCurrentChunk {
            let start = pendingChunkStartIndex ?? currentChunk.startIndex
            remainingChunks.append(String(currentChunk[start...]))
            advancePendingChunk()
        }
        clearPendingMarkdown()
        return remainingChunks.joined()
    }

    private var hasPendingMarkdown: Bool {
        pendingCurrentChunk != nil
    }

    private var pendingCurrentChunk: String? {
        guard pendingChunkIndex < pendingMarkdownChunks.count else {
            return nil
        }

        let chunk = pendingMarkdownChunks[pendingChunkIndex]
        let start = pendingChunkStartIndex ?? chunk.startIndex
        return start < chunk.endIndex ? chunk : nil
    }

    private func appendPendingMarkdown(_ string: String) {
        appendPendingChunk(string)
    }

    private func appendPendingChunk(_ chunk: String) {
        guard !chunk.isEmpty else {
            return
        }
        pendingMarkdownChunks.append(chunk)
    }

    private func advancePendingChunk() {
        pendingChunkIndex += 1
        pendingChunkStartIndex = nil
    }

    private func compactPendingChunksIfNeeded() {
        if pendingChunkIndex == pendingMarkdownChunks.count {
            pendingMarkdownChunks.removeAll(keepingCapacity: true)
            pendingChunkIndex = 0
        } else if pendingChunkIndex > 64 {
            pendingMarkdownChunks.removeFirst(pendingChunkIndex)
            pendingChunkIndex = 0
        }
    }

    private func clearPendingMarkdown() {
        pendingMarkdownChunks.removeAll(keepingCapacity: true)
        pendingChunkIndex = 0
        pendingChunkStartIndex = nil
    }

    // MARK: - Rendering

    private func applyStreamUpdate(_ update: ChatMarkdownStreamUpdate, notify: Bool) {
        for segment in update.completedSegments {
            completedSegmentMarkdown.append(segment)
            if commitCurrentSegment(markdown: segment) {
                completedSegmentRecords.append(currentSegmentRecords)
                currentSegmentRecords = []
                continue
            }

            removeCurrentSegmentViews()
            completedSegmentRecords.append(appendRenderedSegment(segment))
        }

        currentSegmentMarkdown = update.currentSegment
        if let currentSegment = update.currentSegment {
            renderCurrentSegment(currentSegment)
        } else {
            removeCurrentSegmentViews()
        }

        if notify {
            notifyHeightChanged()
        }
    }

    private func commitCurrentSegment(markdown: String) -> Bool {
        guard !currentSegmentRecords.isEmpty else {
            return false
        }

        let renderer = makeRenderer()
        let blocks = renderer.render(markdown: markdown)
        guard ChatMarkdownRenderedBlockViewReconciler.updateAllInPlaceIfPossible(
            currentSegmentRecords,
            with: blocks
        ) else {
            return false
        }

        currentSegmentMarkdown = nil
        return true
    }

    private func renderAllSegments() {
        removeCurrentSegmentViews()
        let renderer = makeRenderer()
        let configuration = blockViewConfiguration(for: renderer)
        var nextRecords: [[ChatMarkdownRenderedBlockViewRecord]] = []
        var startIndex = 0

        for (segmentIndex, segment) in completedSegmentMarkdown.enumerated() {
            let blocks = renderer.render(markdown: segment)
            let records = completedSegmentRecords.indices.contains(segmentIndex)
                ? completedSegmentRecords[segmentIndex]
                : []
            let reconciledRecords = ChatMarkdownRenderedBlockViewReconciler.reconcile(
                blocks,
                records: records,
                in: stackView,
                startingAt: startIndex,
                configuration: configuration
            )
            nextRecords.append(reconciledRecords)
            startIndex += reconciledRecords.count
        }
        completedSegmentRecords = nextRecords

        if let currentSegmentMarkdown {
            renderCurrentSegment(currentSegmentMarkdown)
        }

        notifyHeightChanged()
    }

    @discardableResult
    private func appendRenderedSegment(_ markdown: String) -> [ChatMarkdownRenderedBlockViewRecord] {
        let renderer = makeRenderer()
        return ChatMarkdownRenderedBlockViewReconciler.append(
            renderer.render(markdown: markdown),
            to: stackView,
            configuration: blockViewConfiguration(for: renderer)
        )
    }

    private func renderCurrentSegment(_ markdown: String) {
        let renderer = makeRenderer()
        let blocks = currentSegmentBlocks(from: renderer.render(markdown: markdown))
        let startIndex = max(0, stackView.arrangedSubviews.count - currentSegmentRecords.count)
        currentSegmentRecords = ChatMarkdownRenderedBlockViewReconciler.reconcile(
            blocks,
            records: currentSegmentRecords,
            in: stackView,
            startingAt: startIndex,
            allowsIdentityChange: true,
            configuration: blockViewConfiguration(for: renderer)
        )
    }

    private func makeRenderer() -> ChatMarkdownRenderer {
        ChatMarkdownRenderer(style: style, traitCollection: traitCollection)
    }

    private func blockViewConfiguration(
        for renderer: ChatMarkdownRenderer
    ) -> ChatMarkdownRenderedBlockViewConfiguration {
        ChatMarkdownRenderedBlockViewConfiguration(
            style: renderer.style,
            traitCollection: traitCollection
        ) { [weak self] in
            self?.notifyHeightChanged()
        }
    }

    private func resetRenderedState() {
        ChatMarkdownRenderedBlockViewReconciler.removeAllArrangedSubviews(in: stackView)
        completedSegmentRecords = []
        currentSegmentRecords = []
        invalidateIntrinsicContentSize()
    }

    private func removeCurrentSegmentViews() {
        ChatMarkdownRenderedBlockViewReconciler.remove(currentSegmentRecords, from: stackView)
        currentSegmentRecords = []
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

    private func currentSegmentBlocks(
        from blocks: [ChatMarkdownRenderedBlock]
    ) -> [ChatMarkdownRenderedBlock] {
        blocks.compactMap(\.currentSegmentRenderableBlock)
    }
}

private extension ChatMarkdownRenderedBlock {
    var currentSegmentRenderableBlock: ChatMarkdownRenderedBlock? {
        switch self {
        case let .text(attributedText):
            return attributedText.length > 0 ? self : nil
        case let .codeBlock(codeBlock):
            return .codeBlock(
                ChatMarkdownCodeBlock(
                    code: codeBlock.code,
                    language: codeBlock.language,
                    isStreaming: true
                )
            )
        case .table, .details:
            return self
        case .mathBlock, .image:
            return nil
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
