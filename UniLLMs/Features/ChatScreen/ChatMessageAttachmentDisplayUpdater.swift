//
//  ChatMessageAttachmentDisplayUpdater.swift
//  UniLLMs
//
//  Applies cached and asynchronously-loaded attachment preview displays to message bubbles.
//  Created by Codex on 2026/6/5.
//

import CoreGraphics
import Foundation

@MainActor
final class ChatMessageAttachmentDisplayUpdater {
    private let messageStackAdapter: ChatMessageStackAdapter
    private let attachmentPreviewDisplayPipeline: ChatAttachmentPreviewDisplayPipeline
    private let thumbnailMaxPointSize: CGFloat

    init(
        messageStackAdapter: ChatMessageStackAdapter,
        attachmentPreviewDisplayPipeline: ChatAttachmentPreviewDisplayPipeline,
        thumbnailMaxPointSize: CGFloat
    ) {
        self.messageStackAdapter = messageStackAdapter
        self.attachmentPreviewDisplayPipeline = attachmentPreviewDisplayPipeline
        self.thumbnailMaxPointSize = thumbnailMaxPointSize
    }

    func cancelMessageLoads() {
        attachmentPreviewDisplayPipeline.cancelMessageLoads()
    }

    func loadDisplays(
        messageID: UUID,
        attachments: [ChatAttachment]
    ) {
        let displays = attachmentPreviewDisplayPipeline.displays(
            for: attachments,
            thumbnailMaxPointSize: thumbnailMaxPointSize,
            scope: .message(messageID)
        ) { [weak messageStackAdapter] displays in
            messageStackAdapter?.updateAttachmentDisplays(
                forMessageID: messageID,
                displays: displays
            )
        }
        messageStackAdapter.updateAttachmentDisplays(
            forMessageID: messageID,
            displays: displays
        )
    }
}
