//
//  ChatMarkdownRenderedBlockReconciliationPlan.swift
//  UniLLMs
//
//  Plans rendered Markdown block view reuse before UIKit stack mutations.
//

import Foundation

struct ChatMarkdownRenderedBlockReconciliationPlan {
    struct Reuse {
        var record: ChatMarkdownRenderedBlockViewRecord
        var block: ChatMarkdownRenderedBlock
        var desiredIndex: Int
    }

    struct Insertion {
        var block: ChatMarkdownRenderedBlock
        var desiredIndex: Int
    }

    enum Operation {
        case reuse(Reuse)
        case insert(Insertion)
    }

    var operations: [Operation]
    var removedRecords: [ChatMarkdownRenderedBlockViewRecord]

    init(
        blocks: [ChatMarkdownRenderedBlock],
        currentRecords: [ChatMarkdownRenderedBlockViewRecord],
        startingAt startIndex: Int,
        allowsIdentityChange: Bool
    ) {
        let renderableBlocks = blocks.compactMap(\.renderableBlockView)
        var operations: [Operation] = []
        var retainedViewIDs = Set<ObjectIdentifier>()
        var shouldRebuildRemainingRecords = false

        for (blockIndex, block) in renderableBlocks.enumerated() {
            let existing = currentRecords.indices.contains(blockIndex)
                ? currentRecords[blockIndex]
                : nil
            let desiredIndex = startIndex + blockIndex

            if !shouldRebuildRemainingRecords,
               let existing,
               Self.canReuse(
                   existing,
                   for: block,
                   allowsIdentityChange: allowsIdentityChange
               ) {
                operations.append(
                    .reuse(
                        Reuse(
                            record: existing,
                            block: block,
                            desiredIndex: desiredIndex
                        )
                    )
                )
                retainedViewIDs.insert(ObjectIdentifier(existing.view))
                continue
            }

            if existing != nil {
                shouldRebuildRemainingRecords = true
            }

            operations.append(
                .insert(
                    Insertion(
                        block: block,
                        desiredIndex: desiredIndex
                    )
                )
            )
        }

        self.operations = operations
        removedRecords = currentRecords.filter {
            !retainedViewIDs.contains(ObjectIdentifier($0.view))
        }
    }

    private static func canReuse(
        _ record: ChatMarkdownRenderedBlockViewRecord,
        for block: ChatMarkdownRenderedBlock,
        allowsIdentityChange: Bool
    ) -> Bool {
        record.kind == block.viewKind
            && (allowsIdentityChange || record.identity == ChatMarkdownRenderedBlockViewIdentity(block))
            && block.supportsInPlaceUpdate
    }
}
