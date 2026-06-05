//
//  ChatAttachmentDraftTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatAttachmentDraftTests: XCTestCase {
    private var rootDirectory: URL!
    private var attachmentStore: ChatAttachmentStore!
    private var draft: ChatAttachmentDraft!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentDraftTests-\(UUID().uuidString)", isDirectory: true)
        attachmentStore = ChatAttachmentStore(rootDirectory: rootDirectory)
        draft = ChatAttachmentDraft(attachmentStore: attachmentStore)
    }

    override func tearDownWithError() throws {
        draft = nil
        attachmentStore = nil
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testConsumePendingAttachmentsClearsDraftWithoutDeletingFiles() throws {
        let attachment = try makeAttachment(filename: "image.jpg", kind: .image)

        draft.append([attachment], privacyModeEnabled: false)
        let consumedAttachments = draft.consumePendingAttachments()

        XCTAssertEqual(consumedAttachments, [attachment])
        XCTAssertTrue(draft.pendingAttachments.isEmpty)
        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))
    }

    func testRemovePendingAttachmentDeletesUnreferencedFile() throws {
        let attachment = try makeAttachment(filename: "document.pdf", kind: .file)

        draft.append([attachment], privacyModeEnabled: false)

        XCTAssertTrue(
            draft.removePendingAttachment(
                id: attachment.id,
                retainedConversationAttachments: []
            )
        )
        XCTAssertTrue(draft.pendingAttachments.isEmpty)
        XCTAssertNil(attachmentStore.fileURL(for: attachment))
    }

    func testRemovePendingAttachmentReportsCleanupCompletionForUnreferencedAttachment() throws {
        let attachment = try makeAttachment(filename: "image.jpg", kind: .image)
        var cleanupResults: [ChatAttachmentCleanupResult] = []
        let reportingDraft = ChatAttachmentDraft(
            attachmentStore: attachmentStore,
            attachmentCleanupDidComplete: { cleanupResults.append($0) }
        )

        reportingDraft.append([attachment], privacyModeEnabled: false)

        XCTAssertTrue(
            reportingDraft.removePendingAttachment(
                id: attachment.id,
                retainedConversationAttachments: []
            )
        )
        XCTAssertEqual(cleanupResults, [
            ChatAttachmentCleanupResult(removedUnreferencedAttachments: [attachment])
        ])
    }

    func testRemovePendingAttachmentKeepsFileReferencedByConversation() throws {
        let attachment = try makeAttachment(filename: "document.pdf", kind: .file)
        var retainedAttachment = attachment
        retainedAttachment.id = UUID()
        var cleanupResults: [ChatAttachmentCleanupResult] = []
        let reportingDraft = ChatAttachmentDraft(
            attachmentStore: attachmentStore,
            attachmentCleanupDidComplete: { cleanupResults.append($0) }
        )

        reportingDraft.append([attachment], privacyModeEnabled: false)

        XCTAssertTrue(
            reportingDraft.removePendingAttachment(
                id: attachment.id,
                retainedConversationAttachments: [retainedAttachment]
            )
        )
        XCTAssertTrue(reportingDraft.pendingAttachments.isEmpty)
        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))
        XCTAssertTrue(cleanupResults.isEmpty)
    }

    func testDiscardPrivateModeAttachmentsDeletesConsumedPrivateAttachments() throws {
        let attachment = try makeAttachment(filename: "private.jpg", kind: .image)
        var cleanupResults: [ChatAttachmentCleanupResult] = []
        let reportingDraft = ChatAttachmentDraft(
            attachmentStore: attachmentStore,
            attachmentCleanupDidComplete: { cleanupResults.append($0) }
        )

        reportingDraft.append([attachment], privacyModeEnabled: true)
        XCTAssertEqual(reportingDraft.consumePendingAttachments(), [attachment])

        reportingDraft.discardPrivateModeAttachments()

        XCTAssertNil(attachmentStore.fileURL(for: attachment))
        XCTAssertEqual(cleanupResults, [
            ChatAttachmentCleanupResult(removedUnreferencedAttachments: [attachment])
        ])
    }

    func testDiscardPrivateModeAttachmentsKeepsDuplicateAssetTrackedAfterRemovingOneDraftItem() throws {
        let attachment = try makeAttachment(filename: "private.jpg", kind: .image)
        var duplicateReference = attachment
        duplicateReference.id = UUID()

        draft.append([attachment, duplicateReference], privacyModeEnabled: true)

        XCTAssertTrue(
            draft.removePendingAttachment(
                id: attachment.id,
                retainedConversationAttachments: []
            )
        )
        XCTAssertEqual(draft.pendingAttachments, [duplicateReference])
        XCTAssertNotNil(attachmentStore.fileURL(for: duplicateReference))

        draft.discardPrivateModeAttachments()

        XCTAssertNil(attachmentStore.fileURL(for: duplicateReference))
    }

    func testRestoringSamePrivateAttachmentDoesNotLeaveStalePrivateReferenceAfterRemoval() throws {
        let attachment = try makeAttachment(filename: "restored.jpg", kind: .image)

        draft.append([attachment], privacyModeEnabled: true)
        XCTAssertEqual(draft.consumePendingAttachments(), [attachment])

        draft.append([attachment], privacyModeEnabled: true)
        XCTAssertTrue(
            draft.removePendingAttachment(
                id: attachment.id,
                retainedConversationAttachments: []
            )
        )
        XCTAssertNil(attachmentStore.fileURL(for: attachment))

        let restoredFileURL = rootDirectory.appendingPathComponent(attachment.relativePath)
        try Data("restored".utf8).write(to: restoredFileURL)
        draft.discardPrivateModeAttachments()

        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))
    }

    func testClearPendingAttachmentsWithoutDeletingFilesOnlyClearsDraft() throws {
        let attachment = try makeAttachment(filename: "draft.jpg", kind: .image)

        draft.append([attachment], privacyModeEnabled: true)

        XCTAssertTrue(
            draft.clearPendingAttachments(
                deleteFiles: false,
                retainedConversationAttachments: []
            )
        )
        XCTAssertTrue(draft.pendingAttachments.isEmpty)
        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))
    }

    func testClearPendingAttachmentsWithoutDeletingFilesDoesNotReportCleanupCompletion() throws {
        let attachment = try makeAttachment(filename: "draft.jpg", kind: .image)
        var cleanupResults: [ChatAttachmentCleanupResult] = []
        let reportingDraft = ChatAttachmentDraft(
            attachmentStore: attachmentStore,
            attachmentCleanupDidComplete: { cleanupResults.append($0) }
        )

        reportingDraft.append([attachment], privacyModeEnabled: true)

        XCTAssertTrue(
            reportingDraft.clearPendingAttachments(
                deleteFiles: false,
                retainedConversationAttachments: []
            )
        )
        XCTAssertTrue(cleanupResults.isEmpty)
    }

    func testRemovePendingAttachmentReportsCleanupFailure() {
        var failures: [Error] = []
        let failingDraft = ChatAttachmentDraft(
            attachmentStore: FailingAttachmentCleanupStore(),
            didFail: { error in
                failures.append(error)
            }
        )
        let attachment = ChatAttachment(
            kind: .file,
            filename: "broken.txt",
            contentType: "text/plain",
            relativePath: "broken.txt"
        )

        failingDraft.append([attachment], privacyModeEnabled: false)

        XCTAssertTrue(
            failingDraft.removePendingAttachment(
                id: attachment.id,
                retainedConversationAttachments: []
            )
        )
        XCTAssertTrue(failingDraft.pendingAttachments.isEmpty)
        XCTAssertEqual(failures.count, 1)
    }

    private func makeAttachment(
        filename: String,
        kind: ChatAttachment.Kind
    ) throws -> ChatAttachment {
        try attachmentStore.store(
            data: Data("payload".utf8),
            filename: filename,
            kind: kind,
            contentType: kind == .image ? "image/jpeg" : "application/pdf"
        )
    }
}

private struct FailingAttachmentCleanupStore: ChatAttachmentCleanupStore {
    func deleteUnreferencedAttachments(
        removing removedAttachments: [ChatAttachment],
        referencedBy retainedAttachments: [ChatAttachment]
    ) throws -> ChatAttachmentCleanupResult {
        throw AttachmentCleanupFailure.sample
    }
}

private enum AttachmentCleanupFailure: Error {
    case sample
}
