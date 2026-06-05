//
//  ChatComposerAttachmentWorkflow.swift
//  UniLLMs
//
//  Coordinates composer attachment draft state, import results, preview, and thumbnail presentation.
//  Created by Codex on 2026/6/5.
//

import UIKit

@MainActor
final class ChatComposerAttachmentWorkflow {
    typealias PrivacyModeProvider = @MainActor () -> Bool
    typealias RetainedAttachmentsProvider = @MainActor () -> [ChatAttachment]
    typealias PendingDisplayUpdater = @MainActor ([ChatPendingAttachmentDisplay]) -> Void

    private let attachmentDraft: ChatAttachmentDraft
    private let previewWorkflow: ChatAttachmentPreviewWorkflow
    private let previewDisplayPipeline: ChatAttachmentPreviewDisplayPipeline
    private let privacyModeEnabled: PrivacyModeProvider
    private let retainedConversationAttachments: RetainedAttachmentsProvider
    private let thumbnailMaxPointSize: CGFloat
    private let updatePendingDisplays: PendingDisplayUpdater

    init(
        attachmentDraft: ChatAttachmentDraft,
        previewWorkflow: ChatAttachmentPreviewWorkflow,
        previewDisplayPipeline: ChatAttachmentPreviewDisplayPipeline,
        privacyModeEnabled: @escaping PrivacyModeProvider,
        retainedConversationAttachments: @escaping RetainedAttachmentsProvider,
        thumbnailMaxPointSize: CGFloat,
        updatePendingDisplays: @escaping PendingDisplayUpdater
    ) {
        self.attachmentDraft = attachmentDraft
        self.previewWorkflow = previewWorkflow
        self.previewDisplayPipeline = previewDisplayPipeline
        self.privacyModeEnabled = privacyModeEnabled
        self.retainedConversationAttachments = retainedConversationAttachments
        self.thumbnailMaxPointSize = thumbnailMaxPointSize
        self.updatePendingDisplays = updatePendingDisplays
    }

    var pendingAttachments: [ChatAttachment] {
        attachmentDraft.pendingAttachments
    }

    func append(_ attachments: [ChatAttachment]) {
        guard !attachments.isEmpty else {
            return
        }

        attachmentDraft.append(
            attachments,
            privacyModeEnabled: privacyModeEnabled()
        )
        refreshPendingAttachmentPreview()
    }

    @discardableResult
    func removePendingAttachment(id: UUID) -> Bool {
        guard attachmentDraft.removePendingAttachment(
            id: id,
            retainedConversationAttachments: retainedConversationAttachments()
        ) else {
            return false
        }

        refreshPendingAttachmentPreview()
        return true
    }

    @discardableResult
    func clearPendingAttachments(deleteFiles: Bool = false) -> Bool {
        guard attachmentDraft.clearPendingAttachments(
            deleteFiles: deleteFiles,
            retainedConversationAttachments: retainedConversationAttachments()
        ) else {
            return false
        }

        refreshPendingAttachmentPreview()
        return true
    }

    func discardPrivateModeAttachments(including attachments: [ChatAttachment] = []) {
        attachmentDraft.discardPrivateModeAttachments(including: attachments)
    }

    func consumePendingAttachments() -> [ChatAttachment] {
        let attachments = attachmentDraft.consumePendingAttachments()
        refreshPendingAttachmentPreview()
        return attachments
    }

    @discardableResult
    func previewPendingAttachment(id: UUID) -> Bool {
        guard let attachment = attachmentDraft.pendingAttachments.first(where: { $0.id == id }) else {
            return false
        }

        previewWorkflow.presentPreview(for: attachment)
        return true
    }

    private func refreshPendingAttachmentPreview() {
        let displays = previewDisplayPipeline.displays(
            for: attachmentDraft.pendingAttachments,
            thumbnailMaxPointSize: thumbnailMaxPointSize,
            scope: .composer
        ) { [weak self] displays in
            self?.updatePendingDisplays(Self.pendingAttachmentDisplays(from: displays))
        }
        updatePendingDisplays(Self.pendingAttachmentDisplays(from: displays))
    }

    private static func pendingAttachmentDisplays(
        from displays: [ChatAttachmentPreviewDisplay]
    ) -> [ChatPendingAttachmentDisplay] {
        displays.map { display in
            ChatPendingAttachmentDisplay(
                id: display.id,
                image: display.thumbnailImage,
                filename: display.filename,
                isFile: display.isFile
            )
        }
    }
}
