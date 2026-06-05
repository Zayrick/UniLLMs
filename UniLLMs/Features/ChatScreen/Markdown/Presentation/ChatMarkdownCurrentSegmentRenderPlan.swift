//
//  ChatMarkdownCurrentSegmentRenderPlan.swift
//  UniLLMs
//
//  Plans which rendered Markdown blocks can appear while a segment is streaming.
//

import Foundation

nonisolated struct ChatMarkdownCurrentSegmentRenderPlan {
    var blocks: [ChatMarkdownRenderedBlock]

    nonisolated init(blocks: [ChatMarkdownRenderedBlock]) {
        self.blocks = blocks.compactMap(Self.currentSegmentRenderableBlock)
    }

    nonisolated private static func currentSegmentRenderableBlock(
        _ block: ChatMarkdownRenderedBlock
    ) -> ChatMarkdownRenderedBlock? {
        switch block {
        case let .text(attributedText):
            return attributedText.length > 0 ? block : nil
        case let .codeBlock(codeBlock):
            return .codeBlock(
                ChatMarkdownCodeBlock(
                    code: codeBlock.code,
                    language: codeBlock.language,
                    isStreaming: true
                )
            )
        case .table, .details:
            return block
        case let .blockQuote(blockQuoteBlock):
            let children = blockQuoteBlock.children.compactMap(Self.currentSegmentRenderableBlock)
            return children.isEmpty ? nil : .blockQuote(ChatMarkdownBlockQuoteBlock(children: children))
        case let .list(listBlock):
            let items = listBlock.items.compactMap { item -> ChatMarkdownListItemBlock? in
                let children = item.children.compactMap(Self.currentSegmentRenderableBlock)
                guard !children.isEmpty else {
                    return nil
                }
                return ChatMarkdownListItemBlock(marker: item.marker, children: children)
            }
            return items.isEmpty ? nil : .list(ChatMarkdownListBlock(isOrdered: listBlock.isOrdered, items: items))
        case .mathBlock:
            return block
        case .image:
            return nil
        }
    }
}
