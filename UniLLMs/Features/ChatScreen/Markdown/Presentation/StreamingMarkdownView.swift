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

private enum StreamingMarkdownRenderedKind: Equatable {
    case text
    case codeBlock
    case mathBlock
    case table
    case image
    case details
}

final class StreamingMarkdownView: UIView {
    private enum Scheduling {
        static let maxCharactersPerFlush = 4096
    }

    private struct RenderedRecord {
        let view: UIView
        let kind: StreamingMarkdownRenderedKind
    }

    private let stackView = UIStackView()
    private var segmenter = ChatMarkdownStreamSegmenter()
    private var completedSegmentMarkdown: [String] = []
    private var currentSegmentMarkdown: String?
    private var currentSegmentRecords: [RenderedRecord] = []
    private var traitChangeRegistration: (any UITraitChangeRegistration)?
    var onNeedsHeightUpdate: (() -> Void)?

    private var pendingMarkdownChunks: [String] = []
    private var pendingChunkIndex = 0
    private var pendingChunkStartIndex: String.Index?
    private var pendingCarriageReturn = false
    private var shouldDropLeadingLineFeedAfterFlushedCarriageReturn = false
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var framesToSkip: Int = 0
    private var lastRenderDuration: CFTimeInterval = 0

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

        appendPendingMarkdown(string)
        startDisplayLinkIfNeeded()
    }

    func setFinishedMarkdown(_ markdown: String) {
        stopDisplayLink()
        clearPendingMarkdown()
        resetRenderedState()
        segmenter.reset()
        completedSegmentMarkdown = markdown.isEmpty ? [] : [markdown]
        currentSegmentMarkdown = nil

        if !markdown.isEmpty {
            appendRenderedSegment(markdown)
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

        flushPendingMarkdown(limitToFrameBudget: true, notify: true)

        if !hasPendingMarkdown {
            stopDisplayLink()
        }
    }

    private func flushPendingMarkdown(limitToFrameBudget: Bool, notify: Bool) {
        flushPendingCarriageReturnIfNeeded()
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
        pendingCarriageReturn || pendingCurrentChunk != nil
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
        var text = string

        if shouldDropLeadingLineFeedAfterFlushedCarriageReturn {
            if text.first == "\n" {
                text.removeFirst()
            }
            shouldDropLeadingLineFeedAfterFlushedCarriageReturn = false
        }

        if pendingCarriageReturn {
            if text.first == "\n" {
                text.removeFirst()
            }
            appendPendingChunk("\n")
            pendingCarriageReturn = false
        }

        if text.last == "\r" {
            pendingCarriageReturn = true
            text.removeLast()
        }

        appendPendingChunk(Self.normalizedLineEndings(text))
    }

    private func flushPendingCarriageReturnIfNeeded() {
        guard pendingCarriageReturn else {
            return
        }
        appendPendingChunk("\n")
        pendingCarriageReturn = false
        shouldDropLeadingLineFeedAfterFlushedCarriageReturn = true
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
        pendingCarriageReturn = false
        shouldDropLeadingLineFeedAfterFlushedCarriageReturn = false
    }

    private static func normalizedLineEndings(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: - Rendering

    private func applyStreamUpdate(_ update: ChatMarkdownStreamUpdate, notify: Bool) {
        for segment in update.completedSegments {
            completedSegmentMarkdown.append(segment)
            if commitCurrentSegment(markdown: segment) {
                continue
            }

            let currentDetailsExpansionStates = detailsExpansionStates(in: stackView)
            removeCurrentSegmentViews()
            let detailsStartIndex = detailsExpansionStates(in: stackView).count
            appendRenderedSegment(segment)
            restoreDetailsExpansionStates(
                Array(currentDetailsExpansionStates.dropFirst(detailsStartIndex)),
                startingAt: detailsStartIndex,
                in: stackView
            )
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
        guard blocks.count == currentSegmentRecords.count,
              zip(currentSegmentRecords, blocks).allSatisfy({ pair in
                  pair.0.kind == pair.1.kind
              }) else {
            return false
        }

        for (record, block) in zip(currentSegmentRecords, blocks) {
            guard update(record, with: block) != nil else {
                return false
            }
        }

        currentSegmentRecords = []
        currentSegmentMarkdown = nil
        return true
    }

    private func renderAllSegments() {
        let restoredDetailsExpansionStates = detailsExpansionStates(in: stackView)
        resetRenderedState()

        for segment in completedSegmentMarkdown {
            appendRenderedSegment(segment)
        }

        if let currentSegmentMarkdown {
            renderCurrentSegment(currentSegmentMarkdown)
        }

        restoreDetailsExpansionStates(restoredDetailsExpansionStates, in: stackView)
        notifyHeightChanged()
    }

    private func appendRenderedSegment(_ markdown: String) {
        let renderer = makeRenderer()
        for block in renderer.render(markdown: markdown) {
            guard let record = makeRecord(for: block, renderer: renderer) else {
                continue
            }
            stackView.addArrangedSubview(record.view)
        }
    }

    private func renderCurrentSegment(_ markdown: String) {
        let renderer = makeRenderer()
        let blocks = renderer.render(markdown: markdown).compactMap(\.currentSegmentRenderableBlock)
        let startIndex = max(0, stackView.arrangedSubviews.count - currentSegmentRecords.count)
        var nextRecords: [RenderedRecord] = []

        for (blockIndex, block) in blocks.enumerated() {
            let existing = currentSegmentRecords.indices.contains(blockIndex)
                ? currentSegmentRecords[blockIndex]
                : nil
            let desiredIndex = startIndex + blockIndex

            if let existing,
               let updated = update(existing, with: block) {
                ensureView(updated.view, at: desiredIndex)
                nextRecords.append(updated)
                continue
            }

            if let existing {
                removeView(existing.view)
            }

            guard let record = makeRecord(for: block, renderer: renderer) else {
                continue
            }
            insertView(record.view, at: desiredIndex)
            nextRecords.append(record)
        }

        for record in currentSegmentRecords.dropFirst(nextRecords.count) {
            removeView(record.view)
        }
        currentSegmentRecords = nextRecords
    }

    private func update(
        _ record: RenderedRecord,
        with block: ChatMarkdownRenderedBlock
    ) -> RenderedRecord? {
        guard record.kind == block.kind else {
            return nil
        }

        switch block {
        case let .text(attributedText):
            guard let textView = record.view as? ChatMarkdownTextView else {
                return nil
            }
            textView.replaceMarkdownAttributedText(attributedText)
            return record

        case let .codeBlock(codeBlock):
            guard let codeBlockView = record.view as? ChatMarkdownCodeBlockView else {
                return nil
            }
            codeBlockView.update(codeBlock: codeBlock)
            return record

        case let .table(tableData):
            guard let tableView = record.view as? ChatMarkdownTableView else {
                return nil
            }
            tableView.update(tableData: tableData)
            return record

        case let .details(detailsBlock):
            guard let detailsView = record.view as? ChatMarkdownDetailsView else {
                return nil
            }
            detailsView.update(detailsBlock: detailsBlock)
            return record

        case .mathBlock, .image:
            return nil
        }
    }

    private func makeRecord(
        for block: ChatMarkdownRenderedBlock,
        renderer: ChatMarkdownRenderer
    ) -> RenderedRecord? {
        switch block {
        case let .text(attributedText):
            guard attributedText.length > 0 else {
                return nil
            }
            return RenderedRecord(
                view: ChatMarkdownTextView(attributedText: attributedText),
                kind: .text
            )

        case let .codeBlock(codeBlock):
            return RenderedRecord(
                view: ChatMarkdownCodeBlockView(
                    codeBlock: codeBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                ),
                kind: .codeBlock
            )

        case let .mathBlock(mathBlock):
            return RenderedRecord(
                view: ChatMarkdownMathBlockView(
                    mathBlock: mathBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                ),
                kind: .mathBlock
            )

        case let .table(tableData):
            return RenderedRecord(
                view: ChatMarkdownTableView(
                    tableData: tableData,
                    style: renderer.style,
                    traitCollection: traitCollection
                ),
                kind: .table
            )

        case let .image(imageBlock):
            let imageView = ChatMarkdownImageView(
                imageBlock: imageBlock,
                style: renderer.style,
                traitCollection: traitCollection
            )
            imageView.onImageSizeDidChange = { [weak self] in
                self?.notifyHeightChanged()
            }
            return RenderedRecord(view: imageView, kind: .image)

        case let .details(detailsBlock):
            let detailsView = ChatMarkdownDetailsView(
                detailsBlock: detailsBlock,
                style: renderer.style,
                traitCollection: traitCollection
            )
            detailsView.onNeedsHeightUpdate = { [weak self] in
                self?.notifyHeightChanged()
            }
            return RenderedRecord(view: detailsView, kind: .details)
        }
    }

    private func makeRenderer() -> ChatMarkdownRenderer {
        ChatMarkdownRenderer(traitCollection: traitCollection)
    }

    private func resetRenderedState() {
        for view in stackView.arrangedSubviews {
            removeView(view)
        }
        currentSegmentRecords = []
        invalidateIntrinsicContentSize()
    }

    private func removeCurrentSegmentViews() {
        for record in currentSegmentRecords {
            removeView(record.view)
        }
        currentSegmentRecords = []
    }

    private func removeView(_ view: UIView) {
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    private func insertView(_ view: UIView, at index: Int) {
        stackView.insertArrangedSubview(view, at: clampedArrangedSubviewIndex(index))
    }

    private func ensureView(_ view: UIView, at index: Int) {
        guard let currentIndex = stackView.arrangedSubviews.firstIndex(of: view),
              currentIndex != index else {
            return
        }
        stackView.removeArrangedSubview(view)
        insertView(view, at: index)
    }

    private func clampedArrangedSubviewIndex(_ index: Int) -> Int {
        max(0, min(index, stackView.arrangedSubviews.count))
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

    private func detailsExpansionStates(in rootView: UIView) -> [Bool] {
        var states: [Bool] = []
        appendDetailsExpansionStates(from: rootView, to: &states)
        return states
    }

    private func appendDetailsExpansionStates(from view: UIView, to states: inout [Bool]) {
        if let detailsView = view as? ChatMarkdownDetailsView {
            states.append(detailsView.restoredExpansionState)
        }

        for subview in view.subviews {
            appendDetailsExpansionStates(from: subview, to: &states)
        }
    }

    private func restoreDetailsExpansionStates(_ states: [Bool], in rootView: UIView) {
        var index = 0
        restoreDetailsExpansionStates(states, from: rootView, index: &index)
    }

    private func restoreDetailsExpansionStates(
        _ states: [Bool],
        startingAt startIndex: Int,
        in rootView: UIView
    ) {
        var visitedIndex = 0
        var restoreIndex = 0
        restoreDetailsExpansionStates(
            states,
            startingAt: startIndex,
            from: rootView,
            visitedIndex: &visitedIndex,
            restoreIndex: &restoreIndex
        )
    }

    private func restoreDetailsExpansionStates(_ states: [Bool], from view: UIView, index: inout Int) {
        if let detailsView = view as? ChatMarkdownDetailsView,
           states.indices.contains(index) {
            detailsView.restoreExpansionState(states[index])
            index += 1
        }

        for subview in view.subviews {
            restoreDetailsExpansionStates(states, from: subview, index: &index)
        }
    }

    private func restoreDetailsExpansionStates(
        _ states: [Bool],
        startingAt startIndex: Int,
        from view: UIView,
        visitedIndex: inout Int,
        restoreIndex: inout Int
    ) {
        if let detailsView = view as? ChatMarkdownDetailsView {
            if visitedIndex >= startIndex,
               states.indices.contains(restoreIndex) {
                detailsView.restoreExpansionState(states[restoreIndex])
                restoreIndex += 1
            }
            visitedIndex += 1
        }

        for subview in view.subviews {
            restoreDetailsExpansionStates(
                states,
                startingAt: startIndex,
                from: subview,
                visitedIndex: &visitedIndex,
                restoreIndex: &restoreIndex
            )
        }
    }
}

private extension ChatMarkdownRenderedBlock {
    var kind: StreamingMarkdownRenderedKind {
        switch self {
        case .text:
            return .text
        case .codeBlock:
            return .codeBlock
        case .mathBlock:
            return .mathBlock
        case .table:
            return .table
        case .image:
            return .image
        case .details:
            return .details
        }
    }

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
