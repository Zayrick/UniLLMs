//
//  ChatMarkdownRenderedBlockViewReconciler.swift
//  UniLLMs
//
//  Shared UIKit view reuse for rendered Markdown presentation blocks.
//  Created by Zayrick on 2026/5/22.
//

import UIKit

enum ChatMarkdownRenderedBlockViewAnimation {
    case none
    case streaming

    var isEnabled: Bool {
        self == .streaming
    }

    var duration: TimeInterval {
        0.18
    }
}

struct ChatMarkdownRenderedBlockViewConfiguration {
    let style: ChatMarkdownRenderStyle
    let traitCollection: UITraitCollection
    let animation: ChatMarkdownRenderedBlockViewAnimation
    let onNeedsHeightUpdate: (() -> Void)?

    init(
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection,
        animation: ChatMarkdownRenderedBlockViewAnimation = .none,
        onNeedsHeightUpdate: (() -> Void)? = nil
    ) {
        self.style = style
        self.traitCollection = traitCollection
        self.animation = animation
        self.onNeedsHeightUpdate = onNeedsHeightUpdate
    }
}

struct ChatMarkdownRenderedBlockViewRecord {
    let view: UIView
    let kind: ChatMarkdownRenderedBlockViewKind
    let identity: ChatMarkdownRenderedBlockViewIdentity
}

enum ChatMarkdownRenderedBlockViewKind: Equatable {
    case text
    case codeBlock
    case mathBlock
    case table
    case image
    case details
    case blockQuote
    case list
}

struct ChatMarkdownRenderedBlockViewIdentity: Equatable {
    fileprivate let value: String

    init(_ block: ChatMarkdownRenderedBlock) {
        value = Self.value(for: block)
    }

    private static func value(for block: ChatMarkdownRenderedBlock) -> String {
        switch block {
        case let .text(attributedText):
            return "text:\(attributedText.string)"
        case let .codeBlock(codeBlock):
            return "code:\(codeBlock.language ?? ""):\(codeBlock.code)"
        case let .mathBlock(mathBlock):
            return "math:\(mathBlock.latex)"
        case let .table(tableData):
            return "table:\(tableData.identityValue)"
        case let .image(imageBlock):
            return "image:\(imageBlock.source):\(imageBlock.altText)"
        case let .details(detailsBlock):
            return "details:\(detailsBlock.summary):\(detailsBlock.children.identityValue)"
        case let .blockQuote(blockQuoteBlock):
            return "blockquote:\(blockQuoteBlock.children.identityValue)"
        case let .list(listBlock):
            return "list:\(listBlock.isOrdered):\(listBlock.items.identityValue)"
        }
    }
}

enum ChatMarkdownRenderedBlockViewReconciler {
    @discardableResult
    static func append(
        _ blocks: [ChatMarkdownRenderedBlock],
        to stackView: UIStackView,
        configuration: ChatMarkdownRenderedBlockViewConfiguration
    ) -> [ChatMarkdownRenderedBlockViewRecord] {
        var records: [ChatMarkdownRenderedBlockViewRecord] = []
        for block in renderableBlocks(from: blocks) {
            guard let record = makeRecord(for: block, configuration: configuration) else {
                continue
            }
            records.append(record)
            prepareInsertedViewIfNeeded(record.view, configuration: configuration)
            stackView.addArrangedSubview(record.view)
            animateInsertedViewIfNeeded(record.view, configuration: configuration)
        }
        return records
    }

    static func reconcile(
        _ blocks: [ChatMarkdownRenderedBlock],
        records currentRecords: [ChatMarkdownRenderedBlockViewRecord],
        in stackView: UIStackView,
        startingAt startIndex: Int = 0,
        allowsIdentityChange: Bool = false,
        configuration: ChatMarkdownRenderedBlockViewConfiguration
    ) -> [ChatMarkdownRenderedBlockViewRecord] {
        let blocks = renderableBlocks(from: blocks)
        var nextRecords: [ChatMarkdownRenderedBlockViewRecord] = []
        var shouldRebuildRemainingRecords = false

        for (blockIndex, block) in blocks.enumerated() {
            let existing = currentRecords.indices.contains(blockIndex)
                ? currentRecords[blockIndex]
                : nil
            let desiredIndex = startIndex + blockIndex

            if !shouldRebuildRemainingRecords,
               let existing,
               let updated = update(
                   existing,
                   with: block,
                   allowsIdentityChange: allowsIdentityChange,
                   configuration: configuration
               ) {
                ensureView(updated.view, at: desiredIndex, in: stackView)
                nextRecords.append(updated)
                continue
            }

            if existing != nil {
                shouldRebuildRemainingRecords = true
            }

            guard let record = makeRecord(for: block, configuration: configuration) else {
                continue
            }
            prepareInsertedViewIfNeeded(record.view, configuration: configuration)
            insertView(record.view, at: desiredIndex, in: stackView)
            animateInsertedViewIfNeeded(record.view, configuration: configuration)
            nextRecords.append(record)
        }

        let retainedViews = Set(nextRecords.map { ObjectIdentifier($0.view) })
        for record in currentRecords where !retainedViews.contains(ObjectIdentifier(record.view)) {
            removeView(record.view, from: stackView)
        }

        return nextRecords
    }

    static func updateAllInPlaceIfPossible(
        _ records: [ChatMarkdownRenderedBlockViewRecord],
        with blocks: [ChatMarkdownRenderedBlock],
        allowsIdentityChange: Bool = false,
        animation: ChatMarkdownRenderedBlockViewAnimation = .none
    ) -> Bool {
        let blocks = renderableBlocks(from: blocks)
        guard records.count == blocks.count,
              zip(records, blocks).allSatisfy({ record, block in
                  record.kind == block.viewKind &&
                      (allowsIdentityChange || record.identity == ChatMarkdownRenderedBlockViewIdentity(block)) &&
                      block.supportsInPlaceUpdate
              }) else {
            return false
        }

        for (record, block) in zip(records, blocks) {
            guard update(
                record,
                withAlreadyValidatedBlock: block,
                animatedTextChanges: animation.isEnabled
            ) != nil else {
                return false
            }
        }
        return true
    }

    static func remove(
        _ records: [ChatMarkdownRenderedBlockViewRecord],
        from stackView: UIStackView
    ) {
        for record in records {
            removeView(record.view, from: stackView)
        }
    }

    static func removeAllArrangedSubviews(in stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            removeView(view, from: stackView)
        }
    }

    private static func renderableBlocks(
        from blocks: [ChatMarkdownRenderedBlock]
    ) -> [ChatMarkdownRenderedBlock] {
        blocks.compactMap(\.renderableBlockView)
    }

    private static func update(
        _ record: ChatMarkdownRenderedBlockViewRecord,
        with block: ChatMarkdownRenderedBlock,
        allowsIdentityChange: Bool,
        configuration: ChatMarkdownRenderedBlockViewConfiguration
    ) -> ChatMarkdownRenderedBlockViewRecord? {
        guard record.kind == block.viewKind,
              (allowsIdentityChange || record.identity == ChatMarkdownRenderedBlockViewIdentity(block)),
              block.supportsInPlaceUpdate else {
            return nil
        }
        return update(
            record,
            withAlreadyValidatedBlock: block,
            animatedTextChanges: configuration.animation.isEnabled
        )
    }

    private static func update(
        _ record: ChatMarkdownRenderedBlockViewRecord,
        withAlreadyValidatedBlock block: ChatMarkdownRenderedBlock,
        animatedTextChanges: Bool
    ) -> ChatMarkdownRenderedBlockViewRecord? {
        switch block {
        case let .text(attributedText):
            guard let textView = record.view as? ChatMarkdownTextView else {
                return nil
            }
            textView.replaceMarkdownAttributedText(
                attributedText,
                animated: animatedTextChanges
            )
            return updatedRecord(from: record, for: block)

        case let .codeBlock(codeBlock):
            guard let codeBlockView = record.view as? ChatMarkdownCodeBlockView else {
                return nil
            }
            codeBlockView.update(codeBlock: codeBlock)
            return updatedRecord(from: record, for: block)

        case let .table(tableData):
            guard let tableView = record.view as? ChatMarkdownTableView else {
                return nil
            }
            tableView.update(tableData: tableData)
            return updatedRecord(from: record, for: block)

        case let .details(detailsBlock):
            guard let detailsView = record.view as? ChatMarkdownDetailsView else {
                return nil
            }
            detailsView.update(detailsBlock: detailsBlock)
            return updatedRecord(from: record, for: block)

        case let .blockQuote(blockQuoteBlock):
            guard let blockQuoteView = record.view as? ChatMarkdownBlockQuoteView else {
                return nil
            }
            blockQuoteView.update(blockQuoteBlock: blockQuoteBlock)
            return updatedRecord(from: record, for: block)

        case let .list(listBlock):
            guard let listView = record.view as? ChatMarkdownListView else {
                return nil
            }
            listView.update(listBlock: listBlock)
            return updatedRecord(from: record, for: block)

        case .mathBlock, .image:
            return nil
        }
    }

    private static func updatedRecord(
        from record: ChatMarkdownRenderedBlockViewRecord,
        for block: ChatMarkdownRenderedBlock
    ) -> ChatMarkdownRenderedBlockViewRecord {
        ChatMarkdownRenderedBlockViewRecord(
            view: record.view,
            kind: record.kind,
            identity: ChatMarkdownRenderedBlockViewIdentity(block)
        )
    }

    private static func makeRecord(
        for block: ChatMarkdownRenderedBlock,
        configuration: ChatMarkdownRenderedBlockViewConfiguration
    ) -> ChatMarkdownRenderedBlockViewRecord? {
        switch block {
        case let .text(attributedText):
            guard attributedText.length > 0 else {
                return nil
            }
            return ChatMarkdownRenderedBlockViewRecord(
                view: ChatMarkdownTextView(attributedText: attributedText),
                kind: .text,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        case let .codeBlock(codeBlock):
            return ChatMarkdownRenderedBlockViewRecord(
                view: ChatMarkdownCodeBlockView(
                    codeBlock: codeBlock,
                    style: configuration.style,
                    traitCollection: configuration.traitCollection
                ),
                kind: .codeBlock,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        case let .mathBlock(mathBlock):
            return ChatMarkdownRenderedBlockViewRecord(
                view: ChatMarkdownMathBlockView(
                    mathBlock: mathBlock,
                    style: configuration.style,
                    traitCollection: configuration.traitCollection
                ),
                kind: .mathBlock,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        case let .table(tableData):
            return ChatMarkdownRenderedBlockViewRecord(
                view: ChatMarkdownTableView(
                    tableData: tableData,
                    style: configuration.style,
                    traitCollection: configuration.traitCollection
                ),
                kind: .table,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        case let .image(imageBlock):
            let imageView = ChatMarkdownImageView(
                imageBlock: imageBlock,
                style: configuration.style,
                traitCollection: configuration.traitCollection
            )
            imageView.onImageSizeDidChange = configuration.onNeedsHeightUpdate
            return ChatMarkdownRenderedBlockViewRecord(
                view: imageView,
                kind: .image,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        case let .details(detailsBlock):
            let detailsView = ChatMarkdownDetailsView(
                detailsBlock: detailsBlock,
                style: configuration.style,
                traitCollection: configuration.traitCollection
            )
            detailsView.onNeedsHeightUpdate = configuration.onNeedsHeightUpdate
            return ChatMarkdownRenderedBlockViewRecord(
                view: detailsView,
                kind: .details,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        case let .blockQuote(blockQuoteBlock):
            let blockQuoteView = ChatMarkdownBlockQuoteView(
                blockQuoteBlock: blockQuoteBlock,
                style: configuration.style,
                traitCollection: configuration.traitCollection
            )
            blockQuoteView.onNeedsHeightUpdate = configuration.onNeedsHeightUpdate
            return ChatMarkdownRenderedBlockViewRecord(
                view: blockQuoteView,
                kind: .blockQuote,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        case let .list(listBlock):
            let listView = ChatMarkdownListView(
                listBlock: listBlock,
                style: configuration.style,
                traitCollection: configuration.traitCollection
            )
            listView.onNeedsHeightUpdate = configuration.onNeedsHeightUpdate
            return ChatMarkdownRenderedBlockViewRecord(
                view: listView,
                kind: .list,
                identity: ChatMarkdownRenderedBlockViewIdentity(block)
            )
        }
    }

    private static func removeView(_ view: UIView, from stackView: UIStackView) {
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    private static func insertView(_ view: UIView, at index: Int, in stackView: UIStackView) {
        stackView.insertArrangedSubview(view, at: clampedIndex(index, in: stackView))
    }

    private static func ensureView(_ view: UIView, at index: Int, in stackView: UIStackView) {
        guard let currentIndex = stackView.arrangedSubviews.firstIndex(of: view),
              currentIndex != index else {
            return
        }
        stackView.removeArrangedSubview(view)
        insertView(view, at: index, in: stackView)
    }

    private static func clampedIndex(_ index: Int, in stackView: UIStackView) -> Int {
        max(0, min(index, stackView.arrangedSubviews.count))
    }

    private static func prepareInsertedViewIfNeeded(
        _ view: UIView,
        configuration: ChatMarkdownRenderedBlockViewConfiguration
    ) {
        guard configuration.animation.isEnabled,
              !UIAccessibility.isReduceMotionEnabled else {
            return
        }

        view.alpha = 0.0
    }

    private static func animateInsertedViewIfNeeded(
        _ view: UIView,
        configuration: ChatMarkdownRenderedBlockViewConfiguration
    ) {
        guard configuration.animation.isEnabled,
              !UIAccessibility.isReduceMotionEnabled else {
            view.alpha = 1.0
            return
        }

        UIView.animate(
            withDuration: configuration.animation.duration,
            delay: 0.0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            view.alpha = 1.0
        }
    }
}

extension ChatMarkdownRenderedBlock {
    var viewKind: ChatMarkdownRenderedBlockViewKind {
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
        case .blockQuote:
            return .blockQuote
        case .list:
            return .list
        }
    }

    var renderableBlockView: ChatMarkdownRenderedBlock? {
        switch self {
        case let .text(attributedText):
            return attributedText.length > 0 ? self : nil
        case .codeBlock, .mathBlock, .table, .image, .details, .blockQuote, .list:
            return self
        }
    }

    fileprivate var supportsInPlaceUpdate: Bool {
        switch self {
        case .text, .codeBlock, .table, .details, .blockQuote, .list:
            return true
        case .mathBlock, .image:
            return false
        }
    }
}

private extension Array where Element == ChatMarkdownRenderedBlock {
    var identityValue: String {
        map { ChatMarkdownRenderedBlockViewIdentity($0) }
            .map(\.value)
            .joined(separator: "\u{1F}")
    }
}

private extension Array where Element == ChatMarkdownListItemBlock {
    var identityValue: String {
        map(\.identityValue).joined(separator: "\u{1C}")
    }
}

private extension ChatMarkdownListItemBlock {
    var identityValue: String {
        "\(marker.identityValue):\(children.identityValue)"
    }
}

private extension ChatMarkdownListMarker {
    var identityValue: String {
        switch self {
        case let .text(text):
            return "text:\(text)"
        case let .checkbox(isChecked):
            return "checkbox:\(isChecked)"
        }
    }
}

private extension ChatMarkdownTableData {
    var identityValue: String {
        rows
            .map { row in
                row.map(\.identityValue).joined(separator: "\u{1E}")
            }
            .joined(separator: "\u{1D}")
    }
}

private extension ChatMarkdownTableCell {
    var identityValue: String {
        "\(isHeader):\(alignment.rawValue):\(attributedText.string)"
    }
}
