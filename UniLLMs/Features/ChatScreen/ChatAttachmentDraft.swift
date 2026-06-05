//
//  ChatAttachmentDraft.swift
//  UniLLMs
//
//  Owns pending chat attachment state and private-mode attachment cleanup.
//

import Foundation

final class ChatAttachmentDraft {
    private let attachmentStore: any ChatAttachmentCleanupStore
    private let attachmentCleanupDidComplete: (ChatAttachmentCleanupResult) -> Void
    private let didFail: (Error) -> Void
    private var privateModeAttachmentReferences: [ChatAttachment] = []

    private(set) var pendingAttachments: [ChatAttachment] = []

    init(
        attachmentStore: any ChatAttachmentCleanupStore = ChatAttachmentStore.shared,
        attachmentCleanupDidComplete: @escaping (ChatAttachmentCleanupResult) -> Void = { _ in },
        didFail: @escaping (Error) -> Void = { _ in }
    ) {
        self.attachmentStore = attachmentStore
        self.attachmentCleanupDidComplete = attachmentCleanupDidComplete
        self.didFail = didFail
    }

    func append(_ attachments: [ChatAttachment], privacyModeEnabled: Bool) {
        guard !attachments.isEmpty else {
            return
        }

        if privacyModeEnabled {
            for attachment in attachments where !privateModeAttachmentReferences.contains(attachment) {
                privateModeAttachmentReferences.append(attachment)
            }
        }
        pendingAttachments.append(contentsOf: attachments)
    }

    @discardableResult
    func removePendingAttachment(
        id: UUID,
        retainedConversationAttachments: [ChatAttachment]
    ) -> Bool {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let attachment = pendingAttachments.remove(at: index)
        deletePendingAttachments([attachment], retainedConversationAttachments: retainedConversationAttachments)
        return true
    }

    @discardableResult
    func clearPendingAttachments(
        deleteFiles: Bool = false,
        retainedConversationAttachments: [ChatAttachment]
    ) -> Bool {
        guard !pendingAttachments.isEmpty else {
            return false
        }

        let attachments = pendingAttachments
        pendingAttachments.removeAll()
        if deleteFiles {
            deletePendingAttachments(attachments, retainedConversationAttachments: retainedConversationAttachments)
        }
        return true
    }

    func consumePendingAttachments() -> [ChatAttachment] {
        let attachments = pendingAttachments
        pendingAttachments.removeAll()
        return attachments
    }

    func discardPrivateModeAttachments(including attachments: [ChatAttachment] = []) {
        let attachmentsToDelete = privateModeAttachmentReferences + attachments
        guard !attachmentsToDelete.isEmpty else {
            return
        }

        privateModeAttachmentReferences.removeAll()
        deleteUnreferencedAttachments(
            removing: attachmentsToDelete,
            referencedBy: []
        )
    }

    private func deletePendingAttachments(
        _ attachments: [ChatAttachment],
        retainedConversationAttachments: [ChatAttachment]
    ) {
        guard !attachments.isEmpty else {
            return
        }

        removePrivateModeReferences(for: attachments)
        deleteUnreferencedAttachments(
            removing: attachments,
            referencedBy: retainedConversationAttachments + pendingAttachments
        )
    }

    private func deleteUnreferencedAttachments(
        removing removedAttachments: [ChatAttachment],
        referencedBy retainedAttachments: [ChatAttachment]
    ) {
        do {
            let result = try attachmentStore.deleteUnreferencedAttachments(
                removing: removedAttachments,
                referencedBy: retainedAttachments
            )
            guard !result.isEmpty else {
                return
            }

            attachmentCleanupDidComplete(result)
        } catch {
            didFail(error)
        }
    }

    private func removePrivateModeReferences(for attachments: [ChatAttachment]) {
        for attachment in attachments {
            guard let index = privateModeAttachmentReferences.firstIndex(of: attachment) else {
                continue
            }
            privateModeAttachmentReferences.remove(at: index)
        }
    }
}
