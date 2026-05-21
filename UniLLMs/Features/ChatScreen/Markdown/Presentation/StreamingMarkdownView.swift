//
//  StreamingMarkdownView.swift
//  UniLLMs
//
//  UIView that renders accumulated streamed Markdown as presentation blocks.
//  Now backed by `IncrementalMarkdownLineParser`: tokens flow into a per-block
//  data structure with stable IDs, and a CADisplayLink-driven tick diffs the
//  current block list against the rendered view tree, mutating individual
//  block views in place instead of rebuilding the segment. Predictive
//  completion (`InlineMarkdownAutoCloser`) keeps emphasis/links visually stable
//  while their closing markers are still in flight.
//
//  Created by Zayrick on 2026/5/12.
//

import UIKit

final class StreamingMarkdownView: UIView {
    // MARK: - Per-block render record

    private struct RenderedRecord {
        var view: UIView
        var revision: UInt64
        /// The form the view was last built for. When the block transitions
        /// (e.g. an open fence becomes textual or a textual block is promoted
        /// to a table) the view must be replaced rather than updated in place.
        var formKey: FormKey
    }

    private enum FormKey: Equatable {
        case text
        case codeBlock
        case openMathPlaceholder
        case closedMath
        case table
        case image
        case openDetailsPlaceholder
        case closedDetails
        case thematicBreak
    }

    private let stackView = UIStackView()
    private var parser = IncrementalMarkdownLineParser()
    private var renderedRecords: [IncrementalMarkdownBlockID: RenderedRecord] = [:]
    private var orderedBlockIDs: [IncrementalMarkdownBlockID] = []
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

    // MARK: - External API (preserved)

    func appendMarkdown(_ string: String) {
        guard !string.isEmpty else { return }
        pendingMarkdown.append(string)
        isStreaming = true
        startDisplayLinkIfNeeded()
    }

    func setFinishedMarkdown(_ markdown: String) {
        stopDisplayLink()
        pendingMarkdown = ""
        isStreaming = false
        resetState()

        if !markdown.isEmpty {
            _ = parser.append(markdown)
            _ = parser.finish()
            reconcileBlocks(parser.currentBlocks)
        }

        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    func finishStreamingContent() {
        isStreaming = false
        stopDisplayLink()
        flushPendingMarkdown()
        let finalBlocks = parser.finish()
        reconcileBlocks(finalBlocks)
        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    func resetMarkdown() {
        stopDisplayLink()
        pendingMarkdown = ""
        isStreaming = false
        resetState()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: max(1.0, size.width), height: fittingHeight(for: size.width))
    }

    // MARK: - Setup

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
            view.rebuildAllViews()
        }
    }

    private func resetState() {
        parser.reset()
        for record in renderedRecords.values {
            stackView.removeArrangedSubview(record.view)
            record.view.removeFromSuperview()
        }
        renderedRecords.removeAll()
        orderedBlockIDs.removeAll()
        invalidateIntrinsicContentSize()
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

        if pendingMarkdown.isEmpty {
            // Pause until the next append. Restarted by `appendMarkdown`.
            stopDisplayLink()
        }
    }

    private func flushPendingMarkdown() {
        guard !pendingMarkdown.isEmpty else { return }
        let chunk = pendingMarkdown
        pendingMarkdown = ""

        let start = CACurrentMediaTime()
        let blocks = parser.append(chunk)
        reconcileBlocks(blocks)
        lastRenderDuration = CACurrentMediaTime() - start

        // Adaptive backoff: if the render exceeded the frame budget, skip
        // proportionally many frames so the runloop has room to breathe.
        let frameBudget: CFTimeInterval = 1.0 / 60.0
        if lastRenderDuration > frameBudget {
            framesToSkip = min(Int(lastRenderDuration / frameBudget), 6)
        } else {
            framesToSkip = 0
        }

        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    // MARK: - Reconciliation

    private func reconcileBlocks(_ blocks: [IncrementalMarkdownBlock]) {
        let newIDs = blocks.map(\.id)
        let newIDSet = Set(newIDs)

        // Drop views for IDs that no longer exist (rollback removed them).
        for id in orderedBlockIDs where !newIDSet.contains(id) {
            if let record = renderedRecords.removeValue(forKey: id) {
                stackView.removeArrangedSubview(record.view)
                record.view.removeFromSuperview()
            }
        }

        for (newIndex, block) in blocks.enumerated() {
            if let existing = renderedRecords[block.id] {
                if existing.revision == block.revision {
                    ensureStackOrder(blockID: block.id, atIndex: newIndex)
                    continue
                }
                if updateExistingRecord(existing, with: block, blockID: block.id) {
                    ensureStackOrder(blockID: block.id, atIndex: newIndex)
                    continue
                }
                // Form change → fall through to recreation.
                stackView.removeArrangedSubview(existing.view)
                existing.view.removeFromSuperview()
                renderedRecords.removeValue(forKey: block.id)
            }

            if let record = makeRecord(for: block) {
                renderedRecords[block.id] = record
                insertView(record.view, at: newIndex)
            }
        }

        orderedBlockIDs = newIDs
    }

    private func ensureStackOrder(blockID: IncrementalMarkdownBlockID, atIndex newIndex: Int) {
        guard let view = renderedRecords[blockID]?.view else { return }
        let currentIndex = stackView.arrangedSubviews.firstIndex(of: view)
        if currentIndex != newIndex {
            stackView.removeArrangedSubview(view)
            insertView(view, at: newIndex)
        }
    }

    private func insertView(_ view: UIView, at index: Int) {
        let clampedIndex = max(0, min(index, stackView.arrangedSubviews.count))
        stackView.insertArrangedSubview(view, at: clampedIndex)
    }

    /// Tries to mutate an existing record in place. Returns false when the
    /// block has transitioned form (e.g. textual → table or open math → closed
    /// math) and the caller must rebuild it.
    private func updateExistingRecord(
        _ record: RenderedRecord,
        with block: IncrementalMarkdownBlock,
        blockID: IncrementalMarkdownBlockID
    ) -> Bool {
        let desiredForm = formKey(for: block)
        guard desiredForm == record.formKey else { return false }

        switch desiredForm {
        case .text:
            guard let textView = record.view as? ChatMarkdownTextView else { return false }
            let attributed = renderTextual(block: block)
            textView.replaceTailAttributedText(attributed)

        case .codeBlock:
            guard let codeView = record.view as? ChatMarkdownCodeBlockView else { return false }
            codeView.update(codeBlock: extractCodeBlock(from: block))

        case .openMathPlaceholder:
            guard let textView = record.view as? ChatMarkdownTextView else { return false }
            textView.replaceTailAttributedText(makeMathPlaceholderText(block.rawMarkdown))

        case .table:
            guard let tableView = record.view as? ChatMarkdownTableView,
                  let tableData = renderTable(block: block) else { return false }
            tableView.update(tableData: tableData)

        case .image, .closedMath, .closedDetails, .openDetailsPlaceholder, .thematicBreak:
            // These either render once at close or are cheap enough to rebuild
            // wholesale; signal a form mismatch to force replacement.
            return false
        }

        renderedRecords[blockID] = RenderedRecord(
            view: record.view,
            revision: block.revision,
            formKey: desiredForm
        )
        return true
    }

    private func makeRecord(for block: IncrementalMarkdownBlock) -> RenderedRecord? {
        let form = formKey(for: block)
        switch form {
        case .text:
            let attributed = renderTextual(block: block)
            guard attributed.length > 0 else { return nil }
            let view = ChatMarkdownTextView(attributedText: attributed)
            return RenderedRecord(view: view, revision: block.revision, formKey: form)

        case .codeBlock:
            let renderer = makeRenderer()
            let view = ChatMarkdownCodeBlockView(
                codeBlock: extractCodeBlock(from: block),
                style: renderer.style,
                traitCollection: traitCollection
            )
            return RenderedRecord(view: view, revision: block.revision, formKey: form)

        case .openMathPlaceholder:
            let placeholder = makeMathPlaceholderText(block.rawMarkdown)
            let view = ChatMarkdownTextView(attributedText: placeholder)
            return RenderedRecord(view: view, revision: block.revision, formKey: form)

        case .closedMath:
            let renderer = makeRenderer()
            let blocks = renderer.render(markdown: block.rawMarkdown)
            if case let .mathBlock(mathBlock) = blocks.first {
                let view = ChatMarkdownMathBlockView(
                    mathBlock: mathBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                return RenderedRecord(view: view, revision: block.revision, formKey: form)
            }
            // Fallback: render as plain text if the parser disagreed with the renderer.
            return fallbackTextRecord(for: block.rawMarkdown, revision: block.revision)

        case .table:
            guard let tableData = renderTable(block: block) else {
                return fallbackTextRecord(for: block.rawMarkdown, revision: block.revision)
            }
            let renderer = makeRenderer()
            let view = ChatMarkdownTableView(
                tableData: tableData,
                style: renderer.style,
                traitCollection: traitCollection
            )
            return RenderedRecord(view: view, revision: block.revision, formKey: form)

        case .image:
            let renderer = makeRenderer()
            let blocks = renderer.render(markdown: block.rawMarkdown)
            if case let .image(imageBlock) = blocks.first {
                let view = ChatMarkdownImageView(
                    imageBlock: imageBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                view.onImageSizeDidChange = { [weak self] in
                    self?.handleAsyncContentSizeChange()
                }
                return RenderedRecord(view: view, revision: block.revision, formKey: form)
            }
            return fallbackTextRecord(for: block.rawMarkdown, revision: block.revision)

        case .openDetailsPlaceholder:
            let attributed = renderTextual(block: block, monospaced: true)
            let view = ChatMarkdownTextView(attributedText: attributed)
            return RenderedRecord(view: view, revision: block.revision, formKey: form)

        case .closedDetails:
            let renderer = makeRenderer()
            let blocks = renderer.render(markdown: block.rawMarkdown)
            if case let .details(detailsBlock) = blocks.first {
                let view = ChatMarkdownDetailsView(
                    detailsBlock: detailsBlock,
                    style: renderer.style,
                    traitCollection: traitCollection
                )
                view.onNeedsHeightUpdate = { [weak self] in
                    self?.handleAsyncContentSizeChange()
                }
                return RenderedRecord(view: view, revision: block.revision, formKey: form)
            }
            return fallbackTextRecord(for: block.rawMarkdown, revision: block.revision)

        case .thematicBreak:
            let renderer = makeRenderer()
            let blocks = renderer.render(markdown: block.rawMarkdown)
            if case let .text(attributed) = blocks.first, attributed.length > 0 {
                let view = ChatMarkdownTextView(attributedText: attributed)
                return RenderedRecord(view: view, revision: block.revision, formKey: form)
            }
            return fallbackTextRecord(for: block.rawMarkdown, revision: block.revision)
        }
    }

    private func fallbackTextRecord(for raw: String, revision: UInt64) -> RenderedRecord? {
        let attributed = NSAttributedString(
            string: raw,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        )
        guard attributed.length > 0 else { return nil }
        let view = ChatMarkdownTextView(attributedText: attributed)
        return RenderedRecord(view: view, revision: revision, formKey: .text)
    }

    // MARK: - Form & data extraction

    private func formKey(for block: IncrementalMarkdownBlock) -> FormKey {
        switch block.kind {
        case .textual:
            return .text
        case .fencedCode:
            return .codeBlock
        case .displayMath:
            return block.isClosed ? .closedMath : .openMathPlaceholder
        case .table:
            return .table
        case .image:
            return .image
        case .htmlDetails:
            return block.isClosed ? .closedDetails : .openDetailsPlaceholder
        case .htmlOther:
            return .text
        case .thematicBreak:
            return .thematicBreak
        }
    }

    private func renderTextual(block: IncrementalMarkdownBlock, monospaced: Bool = false) -> NSAttributedString {
        if monospaced {
            let font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
            return NSAttributedString(
                string: block.rawMarkdown,
                attributes: [.font: font, .foregroundColor: UIColor.label]
            )
        }
        let effective = block.isClosed
            ? block.rawMarkdown
            : InlineMarkdownAutoCloser.autoClosed(block.rawMarkdown)
        let renderer = makeRenderer()
        let rendered = renderer.render(markdown: effective)
        let combined = NSMutableAttributedString()
        for piece in rendered {
            if case let .text(attr) = piece {
                if combined.length > 0 { combined.append(NSAttributedString(string: "\n")) }
                combined.append(attr)
            }
        }
        return combined
    }

    private func extractCodeBlock(from block: IncrementalMarkdownBlock) -> ChatMarkdownCodeBlock {
        guard case let .fencedCode(fence, language) = block.kind else {
            return ChatMarkdownCodeBlock(code: block.rawMarkdown, language: nil)
        }
        var lines = block.rawMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Drop the opening fence line (always present once a fenced-code block exists).
        if !lines.isEmpty {
            lines.removeFirst()
        }
        // Drop the closing fence line when closed.
        if block.isClosed, let last = lines.last,
           IncrementalMarkdownLineParser.isFencedCodeClose(last, openingFence: fence) {
            lines.removeLast()
        }
        // Drop a trailing empty element produced by the split when rawMarkdown ended with "\n".
        if let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        let body = lines.joined(separator: "\n")
        return ChatMarkdownCodeBlock(code: body, language: language)
    }

    private func renderTable(block: IncrementalMarkdownBlock) -> ChatMarkdownTableData? {
        let renderer = makeRenderer()
        let blocks = renderer.render(markdown: block.rawMarkdown)
        if case let .table(td) = blocks.first {
            return td
        }
        return nil
    }

    private func makeMathPlaceholderText(_ raw: String) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .regular
        )
        return NSAttributedString(
            string: raw,
            attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]
        )
    }

    private func makeRenderer() -> ChatMarkdownRenderer {
        ChatMarkdownRenderer(traitCollection: traitCollection)
    }

    // MARK: - Trait change

    private func rebuildAllViews() {
        for record in renderedRecords.values {
            stackView.removeArrangedSubview(record.view)
            record.view.removeFromSuperview()
        }
        renderedRecords.removeAll()
        let blocks = parser.currentBlocks
        reconcileBlocks(blocks)
        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    private func handleAsyncContentSizeChange() {
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

