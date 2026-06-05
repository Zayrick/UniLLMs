//
//  ChatAttachmentPreviewDisplayPipelineTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatAttachmentPreviewDisplayPipelineTests: XCTestCase {
    func testDisplaysReturnsPlaceholdersThenPublishesAsyncUpdateAndCachesResult() {
        let attachment = Self.attachment(filename: "photo.png")
        let thumbnail = UIImage()
        let cache = ChatAttachmentThumbnailMemoryCache()
        let loader = FakeAsyncLoader()
        let pipeline = Self.makePipeline(cache: cache, loader: loader)
        var updates: [[ChatAttachmentPreviewDisplay]] = []

        let initialDisplays = pipeline.displays(
            for: [attachment],
            thumbnailMaxPointSize: 48.0,
            scope: .composer
        ) { displays in
            updates.append(displays)
        }

        XCTAssertEqual(initialDisplays.map(\.attachment), [attachment])
        XCTAssertNil(initialDisplays.first?.thumbnailImage)
        loader.completeLoad(
            at: 0,
            results: [
                ChatAttachmentThumbnailLoadResult(attachmentID: attachment.id, thumbnailImage: thumbnail)
            ]
        )

        XCTAssertEqual(updates.count, 1)
        XCTAssertTrue(updates.first?.first?.thumbnailImage === thumbnail)

        let cachedDisplays = pipeline.displays(
            for: [attachment],
            thumbnailMaxPointSize: 48.0,
            scope: .composer
        ) { _ in
            XCTFail("A cached thumbnail should not schedule a follow-up update.")
        }
        XCTAssertTrue(cachedDisplays.first?.thumbnailImage === thumbnail)
        XCTAssertEqual(loader.loads.count, 1)
    }

    func testNewRequestForSameScopeCancelsPreviousLoadAndDropsStaleUpdate() {
        let firstAttachment = Self.attachment(filename: "first.png")
        let secondAttachment = Self.attachment(filename: "second.png")
        let firstThumbnail = UIImage()
        let secondThumbnail = UIImage()
        let loader = FakeAsyncLoader()
        let pipeline = Self.makePipeline(loader: loader)
        var updates: [[ChatAttachmentPreviewDisplay]] = []

        _ = pipeline.displays(
            for: [firstAttachment],
            thumbnailMaxPointSize: 48.0,
            scope: .composer
        ) { displays in
            updates.append(displays)
        }
        _ = pipeline.displays(
            for: [secondAttachment],
            thumbnailMaxPointSize: 48.0,
            scope: .composer
        ) { displays in
            updates.append(displays)
        }

        XCTAssertTrue(loader.loads[0].task.isCancelled)

        loader.completeLoad(
            at: 0,
            results: [
                ChatAttachmentThumbnailLoadResult(attachmentID: firstAttachment.id, thumbnailImage: firstThumbnail)
            ]
        )
        loader.completeLoad(
            at: 1,
            results: [
                ChatAttachmentThumbnailLoadResult(attachmentID: secondAttachment.id, thumbnailImage: secondThumbnail)
            ]
        )

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.map(\.attachment), [secondAttachment])
        XCTAssertTrue(updates.first?.first?.thumbnailImage === secondThumbnail)
    }

    func testCancelScopePreventsFollowUpUpdate() {
        let attachment = Self.attachment(filename: "photo.png")
        let loader = FakeAsyncLoader()
        let pipeline = Self.makePipeline(loader: loader)
        var updates: [[ChatAttachmentPreviewDisplay]] = []

        _ = pipeline.displays(
            for: [attachment],
            thumbnailMaxPointSize: 48.0,
            scope: .message(UUID())
        ) { displays in
            updates.append(displays)
        }
        pipeline.cancelMessageLoads()
        loader.completeLoad(
            at: 0,
            results: [
                ChatAttachmentThumbnailLoadResult(attachmentID: attachment.id, thumbnailImage: UIImage())
            ]
        )

        XCTAssertTrue(loader.loads[0].task.isCancelled)
        XCTAssertTrue(updates.isEmpty)
    }

    func testMismatchedResultIDsAreDropped() {
        let attachment = Self.attachment(filename: "photo.png")
        let loader = FakeAsyncLoader()
        let pipeline = Self.makePipeline(loader: loader)
        var updates: [[ChatAttachmentPreviewDisplay]] = []

        _ = pipeline.displays(
            for: [attachment],
            thumbnailMaxPointSize: 48.0,
            scope: .composer
        ) { displays in
            updates.append(displays)
        }
        loader.completeLoad(
            at: 0,
            results: [
                ChatAttachmentThumbnailLoadResult(attachmentID: UUID(), thumbnailImage: UIImage())
            ]
        )

        XCTAssertTrue(updates.isEmpty)
    }

    private static func makePipeline(
        cache: ChatAttachmentThumbnailMemoryCache? = nil,
        loader: FakeAsyncLoader
    ) -> ChatAttachmentPreviewDisplayPipeline {
        let cache = cache ?? ChatAttachmentThumbnailMemoryCache()
        let thumbnailProvider = ChatAttachmentThumbnailProvider(
            cache: cache,
            scale: { 1.0 }
        )
        return ChatAttachmentPreviewDisplayPipeline(
            displayBuilder: ChatAttachmentPreviewDisplayBuilder(
                thumbnailProvider: thumbnailProvider,
                thumbnailMaxPointSize: 48.0
            ),
            asyncLoader: loader
        )
    }

    private static func attachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .image,
            filename: filename,
            contentType: "image/png",
            relativePath: filename
        )
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
final class ChatAttachmentAsyncThumbnailLoaderTests: XCTestCase {
    func testLoadThumbnailsUsesInjectedSchedulerAndPreservesResultOrder() async {
        let imageWithData = Self.attachment(kind: .image, filename: "photo.png")
        let file = Self.attachment(kind: .file, filename: "notes.pdf")
        let imageWithMissingURL = Self.attachment(kind: .image, filename: "missing-url.png")
        let imageWithMissingData = Self.attachment(kind: .image, filename: "missing-data.png")
        let imageURL = URL(fileURLWithPath: "/tmp/photo.png")
        let missingDataURL = URL(fileURLWithPath: "/tmp/missing-data.png")
        let data = Data([1, 2, 3])
        let thumbnail = UIImage()
        let scheduler = ImmediateThumbnailLoadingScheduler()
        var scaleCalls = 0
        var fileURLLookups: [UUID] = []
        var loadDataURLs: [URL] = []
        var decodeRequests: [(data: Data, maxPointSize: CGFloat, scale: CGFloat)] = []
        let loader = ChatAttachmentAsyncThumbnailLoader(
            fileURL: { attachment in
                fileURLLookups.append(attachment.id)
                switch attachment.id {
                case imageWithData.id:
                    return imageURL
                case imageWithMissingData.id:
                    return missingDataURL
                default:
                    return nil
                }
            },
            loadData: { url in
                loadDataURLs.append(url)
                return url == imageURL ? data : nil
            },
            decodeImage: { requestData, maxPointSize, scale in
                decodeRequests.append((requestData, maxPointSize, scale))
                return thumbnail
            },
            scale: {
                scaleCalls += 1
                return 3.0
            },
            scheduleThumbnailLoad: scheduler.scheduleThumbnailLoad
        )

        let results = await Self.loadResults(
            using: loader,
            attachments: [
                imageWithData,
                file,
                imageWithMissingURL,
                imageWithMissingData
            ],
            thumbnailMaxPointSize: 64.0
        )

        XCTAssertEqual(scheduler.scheduledCount, 1)
        XCTAssertEqual(scaleCalls, 1)
        XCTAssertEqual(results.map(\.attachmentID), [
            imageWithData.id,
            file.id,
            imageWithMissingURL.id,
            imageWithMissingData.id
        ])
        XCTAssertTrue(results[0].thumbnailImage === thumbnail)
        XCTAssertNil(results[1].thumbnailImage)
        XCTAssertNil(results[2].thumbnailImage)
        XCTAssertNil(results[3].thumbnailImage)
        XCTAssertEqual(fileURLLookups, [
            imageWithData.id,
            imageWithMissingURL.id,
            imageWithMissingData.id
        ])
        XCTAssertEqual(loadDataURLs, [imageURL, missingDataURL])
        XCTAssertEqual(decodeRequests.count, 1)
        XCTAssertEqual(decodeRequests[0].data, data)
        XCTAssertEqual(decodeRequests[0].maxPointSize, 64.0)
        XCTAssertEqual(decodeRequests[0].scale, 3.0)
    }

    func testLoadThumbnailsCancellationBeforeScheduledWorkSkipsLoadingAndCompletion() async {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let scheduler = ManualThumbnailLoadingScheduler()
        var didRequestFileURL = false
        var didComplete = false
        let loader = ChatAttachmentAsyncThumbnailLoader(
            fileURL: { _ in
                didRequestFileURL = true
                return URL(fileURLWithPath: "/tmp/photo.png")
            },
            loadData: { _ in Data([1]) },
            decodeImage: { _, _, _ in UIImage() },
            scale: { 1.0 },
            scheduleThumbnailLoad: scheduler.scheduleThumbnailLoad
        )

        let task = loader.loadThumbnails(
            for: [attachment],
            thumbnailMaxPointSize: 48.0
        ) { _ in
            didComplete = true
        }
        XCTAssertEqual(scheduler.pendingCount, 1)

        task.cancel()
        scheduler.runNext()
        await Task.yield()

        XCTAssertFalse(didRequestFileURL)
        XCTAssertFalse(didComplete)
    }

    func testLoadThumbnailsCancellationBeforeMainActorDeliverySkipsCompletion() async {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let scheduler = ManualThumbnailLoadingScheduler()
        var loadDataCount = 0
        var didComplete = false
        let loader = ChatAttachmentAsyncThumbnailLoader(
            fileURL: { _ in URL(fileURLWithPath: "/tmp/photo.png") },
            loadData: { _ in
                loadDataCount += 1
                return Data([1])
            },
            decodeImage: { _, _, _ in UIImage() },
            scale: { 1.0 },
            scheduleThumbnailLoad: scheduler.scheduleThumbnailLoad
        )

        let task = loader.loadThumbnails(
            for: [attachment],
            thumbnailMaxPointSize: 48.0
        ) { _ in
            didComplete = true
        }
        scheduler.runNext()
        task.cancel()
        await Task.yield()

        XCTAssertEqual(loadDataCount, 1)
        XCTAssertFalse(didComplete)
    }

    private static func loadResults(
        using loader: ChatAttachmentAsyncThumbnailLoader,
        attachments: [ChatAttachment],
        thumbnailMaxPointSize: CGFloat
    ) async -> [ChatAttachmentThumbnailLoadResult] {
        await withCheckedContinuation { continuation in
            _ = loader.loadThumbnails(
                for: attachments,
                thumbnailMaxPointSize: thumbnailMaxPointSize
            ) { results in
                continuation.resume(returning: results)
            }
        }
    }

    private static func attachment(
        kind: ChatAttachment.Kind,
        filename: String
    ) -> ChatAttachment {
        ChatAttachment(
            kind: kind,
            filename: filename,
            contentType: kind == .image ? "image/png" : "application/pdf",
            relativePath: filename
        )
    }

    nonisolated private final class ImmediateThumbnailLoadingScheduler {
        private let lock = NSLock()
        private var scheduled = 0

        var scheduledCount: Int {
            lock.withLock {
                scheduled
            }
        }

        func scheduleThumbnailLoad(_ work: @escaping () -> Void) {
            lock.withLock {
                scheduled += 1
            }
            work()
        }
    }

    nonisolated private final class ManualThumbnailLoadingScheduler {
        private let lock = NSLock()
        private var workItems: [() -> Void] = []

        var pendingCount: Int {
            lock.withLock {
                workItems.count
            }
        }

        func scheduleThumbnailLoad(_ work: @escaping () -> Void) {
            lock.withLock {
                workItems.append(work)
            }
        }

        func runNext() {
            let work = lock.withLock {
                workItems.removeFirst()
            }
            work()
        }
    }
}
