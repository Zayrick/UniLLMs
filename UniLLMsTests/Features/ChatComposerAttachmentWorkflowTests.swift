//
//  ChatComposerAttachmentWorkflowTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatComposerAttachmentWorkflowTests: XCTestCase {
    private var rootDirectory: URL!
    private var attachmentStore: ChatAttachmentStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatComposerAttachmentWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        attachmentStore = ChatAttachmentStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        attachmentStore = nil
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testAppendRemoveAndConsumeRefreshPendingDisplays() throws {
        let thumbnail = UIImage()
        let attachment = try makeStoredAttachment(filename: "photo.jpg", kind: .image)
        let environment = makeEnvironment()

        environment.workflow.append([attachment])
        environment.loader.completeLoad(
            at: 0,
            results: [
                ChatAttachmentThumbnailLoadResult(attachmentID: attachment.id, thumbnailImage: thumbnail)
            ]
        )

        XCTAssertEqual(environment.displayUpdates().map { $0.map(\.filename) }, [
            ["photo.jpg"],
            ["photo.jpg"]
        ])
        XCTAssertTrue(environment.displayUpdates()[1].first?.image === thumbnail)

        XCTAssertTrue(environment.workflow.removePendingAttachment(id: attachment.id))

        XCTAssertEqual(environment.displayUpdates().map { $0.map(\.filename) }, [
            ["photo.jpg"],
            ["photo.jpg"],
            []
        ])

        environment.workflow.append([attachment])
        let consumedAttachments = environment.workflow.consumePendingAttachments()

        XCTAssertEqual(consumedAttachments, [attachment])
        XCTAssertTrue(environment.workflow.pendingAttachments.isEmpty)
        XCTAssertEqual(environment.displayUpdates().last, [])
    }

    func testRemoveUsesRetainedConversationAttachmentsProvider() throws {
        let attachment = try makeStoredAttachment(filename: "photo.jpg", kind: .image)
        var retainedAttachment = attachment
        retainedAttachment.id = UUID()
        var retainedProviderCalls = 0
        var cleanupResults: [ChatAttachmentCleanupResult] = []
        let environment = makeEnvironment(
            retainedConversationAttachments: {
                retainedProviderCalls += 1
                return [retainedAttachment]
            },
            attachmentCleanupDidComplete: {
                cleanupResults.append($0)
            }
        )

        environment.workflow.append([attachment])
        XCTAssertTrue(environment.workflow.removePendingAttachment(id: attachment.id))

        XCTAssertEqual(retainedProviderCalls, 1)
        XCTAssertTrue(cleanupResults.isEmpty)
        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))
    }

    func testAppendUsesPrivacyModeProviderForPrivateModeCleanup() throws {
        let attachment = try makeStoredAttachment(filename: "private.jpg", kind: .image)
        var cleanupResults: [ChatAttachmentCleanupResult] = []
        let environment = makeEnvironment(
            privacyModeEnabled: { true },
            attachmentCleanupDidComplete: {
                cleanupResults.append($0)
            }
        )

        environment.workflow.append([attachment])
        _ = environment.workflow.consumePendingAttachments()
        environment.workflow.discardPrivateModeAttachments()

        XCTAssertNil(attachmentStore.fileURL(for: attachment))
        XCTAssertEqual(cleanupResults, [
            ChatAttachmentCleanupResult(removedUnreferencedAttachments: [attachment])
        ])
    }

    func testPreviewPendingOnlyPresentsExistingAttachment() throws {
        let attachment = try makeStoredAttachment(filename: "notes.pdf", kind: .file)
        var previewedAttachments: [ChatAttachment] = []
        let previewWorkflow = CapturingPreviewWorkflow {
            previewedAttachments.append($0)
        }
        let environment = makeEnvironment(previewWorkflow: previewWorkflow.workflow)

        XCTAssertFalse(environment.workflow.previewPendingAttachment(id: attachment.id))

        environment.workflow.append([attachment])

        XCTAssertTrue(environment.workflow.previewPendingAttachment(id: attachment.id))
        XCTAssertEqual(previewedAttachments, [attachment])
    }

    private func makeEnvironment(
        privacyModeEnabled: @escaping ChatComposerAttachmentWorkflow.PrivacyModeProvider = { false },
        retainedConversationAttachments: @escaping ChatComposerAttachmentWorkflow.RetainedAttachmentsProvider = { [] },
        attachmentCleanupDidComplete: @escaping (ChatAttachmentCleanupResult) -> Void = { _ in },
        previewWorkflow: ChatAttachmentPreviewWorkflow? = nil
    ) -> TestEnvironment {
        let cache = ChatAttachmentThumbnailMemoryCache()
        let thumbnailProvider = ChatAttachmentThumbnailProvider(
            cache: cache,
            scale: { 1.0 }
        )
        let loader = FakeAsyncLoader()
        let pipeline = ChatAttachmentPreviewDisplayPipeline(
            displayBuilder: ChatAttachmentPreviewDisplayBuilder(
                thumbnailProvider: thumbnailProvider,
                thumbnailMaxPointSize: 48.0
            ),
            asyncLoader: loader
        )
        var displayUpdates: [[ChatPendingAttachmentDisplay]] = []
        let workflow = ChatComposerAttachmentWorkflow(
            attachmentDraft: ChatAttachmentDraft(
                attachmentStore: attachmentStore,
                attachmentCleanupDidComplete: attachmentCleanupDidComplete
            ),
            previewWorkflow: previewWorkflow ?? CapturingPreviewWorkflow { _ in }.workflow,
            previewDisplayPipeline: pipeline,
            privacyModeEnabled: privacyModeEnabled,
            retainedConversationAttachments: retainedConversationAttachments,
            thumbnailMaxPointSize: 48.0,
            updatePendingDisplays: {
                displayUpdates.append($0)
            }
        )
        return TestEnvironment(
            workflow: workflow,
            loader: loader,
            displayUpdates: { displayUpdates }
        )
    }

    private func makeStoredAttachment(
        filename: String,
        kind: ChatAttachment.Kind
    ) throws -> ChatAttachment {
        try attachmentStore.store(
            data: Data("payload".utf8),
            filename: filename,
            kind: kind,
            contentType: kind == .image ? "image/jpeg" : "text/plain",
            preferredExtension: (filename as NSString).pathExtension
        )
    }

    private struct TestEnvironment {
        let workflow: ChatComposerAttachmentWorkflow
        let loader: FakeAsyncLoader
        let displayUpdates: () -> [[ChatPendingAttachmentDisplay]]
    }

    private final class FakeAsyncLoader: ChatAttachmentPreviewDisplayAsyncLoading {
        struct Load {
            var attachments: [ChatAttachment]
            var thumbnailMaxPointSize: CGFloat
            var completion: @MainActor ([ChatAttachmentThumbnailLoadResult]) -> Void
            var task: FakeLoadTask
        }

        private(set) var loads: [Load] = []

        func loadThumbnails(
            for attachments: [ChatAttachment],
            thumbnailMaxPointSize: CGFloat,
            completion: @escaping @MainActor ([ChatAttachmentThumbnailLoadResult]) -> Void
        ) -> any ChatAttachmentPreviewDisplayLoadTask {
            let task = FakeLoadTask()
            loads.append(
                Load(
                    attachments: attachments,
                    thumbnailMaxPointSize: thumbnailMaxPointSize,
                    completion: completion,
                    task: task
                )
            )
            return task
        }

        func completeLoad(
            at index: Int,
            results: [ChatAttachmentThumbnailLoadResult]
        ) {
            loads[index].completion(results)
        }
    }

    nonisolated private final class FakeLoadTask: ChatAttachmentPreviewDisplayLoadTask {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.withLock {
                cancelled
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
            }
        }
    }
}

@MainActor
private final class CapturingPreviewWorkflow {
    let workflow: ChatAttachmentPreviewWorkflow

    init(preview: @escaping (ChatAttachment) -> Void) {
        workflow = ChatAttachmentPreviewWorkflow(
            previewController: ChatAttachmentPreviewController(
                fileURL: { attachment in
                    preview(attachment)
                    return URL(fileURLWithPath: "/tmp/\(attachment.filename)")
                },
                canPreview: { _ in true }
            ),
            isPresentingModal: { false },
            endEditing: {},
            presentViewController: { _ in },
            presentError: { _ in }
        )
    }
}
