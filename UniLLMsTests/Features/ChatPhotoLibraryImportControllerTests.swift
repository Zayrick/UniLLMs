//
//  ChatPhotoLibraryImportControllerTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatPhotoLibraryImportControllerTests: XCTestCase {
    func testImportsLoadableImagesInOriginalSelectionOrder() async {
        let store = makeAttachmentStore()
        let controller = ChatPhotoLibraryImportController(
            attachmentImporter: makeImporter(store: store)
        )
        var didLoadSkippedItem = false
        var importResult: ChatAttachmentImportResult?

        let didStart = controller.importItems(
            [
                item(suggestedName: " First ", image: UIImage()),
                ChatPhotoLibraryImportItem(
                    suggestedName: "Skipped",
                    canLoadImage: false,
                    loadImage: {
                        didLoadSkippedItem = true
                        return UIImage()
                    }
                ),
                item(suggestedName: nil, image: UIImage())
            ]
        ) { result in
            importResult = result
        }
        await waitUntil { importResult?.attachments.count == 2 }

        XCTAssertTrue(didStart)
        XCTAssertFalse(didLoadSkippedItem)
        XCTAssertEqual(importResult?.attachments.map(\.filename), ["First.jpg", "library-3.jpg"])
        XCTAssertEqual(try? store.loadData(for: importResult!.attachments[0]), Data([0xCA, 0xFE]))
        XCTAssertEqual(importResult?.errors.count, 0)
    }

    func testNilLoadedImageIsSkipped() async {
        let controller = ChatPhotoLibraryImportController(
            attachmentImporter: makeImporter(store: makeAttachmentStore())
        )
        var importResult: ChatAttachmentImportResult?

        controller.importItems(
            [
                ChatPhotoLibraryImportItem(
                    suggestedName: "Missing",
                    canLoadImage: true,
                    loadImage: { nil }
                )
            ]
        ) { result in
            importResult = result
        }
        await waitUntil { importResult != nil }

        XCTAssertEqual(importResult?.attachments ?? [], [])
        XCTAssertEqual(importResult?.errors.count, 0)
    }

    func testImportEncodingFailureReportsError() async {
        let controller = ChatPhotoLibraryImportController(
            attachmentImporter: makeImporter(store: makeAttachmentStore(), jpegData: nil)
        )
        var importResult: ChatAttachmentImportResult?

        controller.importItems(
            [item(suggestedName: "Broken", image: UIImage())]
        ) { result in
            importResult = result
        }
        await waitUntil { importResult != nil }

        XCTAssertEqual(importResult?.attachments ?? [], [])
        XCTAssertEqual(importResult?.errors.map(\.localizedDescription), [
            ChatAttachmentImporterError.imageEncodingFailed.localizedDescription
        ])
    }

    func testPartialImportReturnsSuccessfulAttachmentsAndReportsFailure() async {
        let store = makeAttachmentStore()
        var encodeAttemptCount = 0
        let importer = ChatAttachmentImporter(
            attachmentStore: store,
            filenames: ChatAttachmentImportFilenames(
                capturedPhotoFilename: { "captured-\($0).jpg" },
                photoLibraryImageFilename: { "library-\($0).jpg" }
            ),
            jpegData: { _, _ in
                encodeAttemptCount += 1
                return encodeAttemptCount == 1 ? Data([0xCA, 0xFE]) : nil
            }
        )
        let controller = ChatPhotoLibraryImportController(attachmentImporter: importer)
        var importResult: ChatAttachmentImportResult?

        controller.importItems(
            [
                item(suggestedName: "Good", image: UIImage()),
                item(suggestedName: "Bad", image: UIImage())
            ]
        ) { result in
            importResult = result
        }
        await waitUntil { importResult != nil }

        XCTAssertEqual(importResult?.attachments.map(\.filename), ["Good.jpg"])
        XCTAssertEqual(importResult?.errors.map(\.localizedDescription), [
            ChatAttachmentImporterError.imageEncodingFailed.localizedDescription
        ])
    }

    func testCancelSuppressesLateImportCallback() async {
        let controller = ChatPhotoLibraryImportController(
            attachmentImporter: makeImporter(store: makeAttachmentStore())
        )
        var imageContinuation: CheckedContinuation<UIImage?, Never>?
        var importResult: ChatAttachmentImportResult?

        controller.importItems(
            [
                ChatPhotoLibraryImportItem(
                    suggestedName: "Late",
                    canLoadImage: true,
                    loadImage: {
                        await withCheckedContinuation { continuation in
                            imageContinuation = continuation
                        }
                    }
                )
            ]
        ) { result in
            importResult = result
        }
        await waitUntil { imageContinuation != nil }

        controller.cancel()
        imageContinuation?.resume(returning: UIImage())
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertNil(importResult)
    }

    func testStartingNewImportSuppressesPreviousImportCallback() async {
        let controller = ChatPhotoLibraryImportController(
            attachmentImporter: makeImporter(store: makeAttachmentStore())
        )
        var firstContinuation: CheckedContinuation<UIImage?, Never>?
        var importedFilenames: [[String]] = []

        controller.importItems(
            [
                ChatPhotoLibraryImportItem(
                    suggestedName: "First",
                    canLoadImage: true,
                    loadImage: {
                        await withCheckedContinuation { continuation in
                            firstContinuation = continuation
                        }
                    }
                )
            ]
        ) { result in
            importedFilenames.append(result.attachments.map(\.filename))
        }
        await waitUntil { firstContinuation != nil }

        controller.importItems(
            [item(suggestedName: "Second", image: UIImage())]
        ) { result in
            importedFilenames.append(result.attachments.map(\.filename))
        }
        await waitUntil { importedFilenames.count == 1 }

        firstContinuation?.resume(returning: UIImage())
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(importedFilenames, [["Second.jpg"]])
    }

    func testEmptyImportDoesNotStartWork() {
        let controller = ChatPhotoLibraryImportController(
            attachmentImporter: makeImporter(store: makeAttachmentStore())
        )

        let didStart = controller.importItems([]) { _ in
            XCTFail("Empty imports should not invoke callback.")
        }

        XCTAssertFalse(didStart)
    }

    private func item(
        suggestedName: String?,
        image: UIImage?
    ) -> ChatPhotoLibraryImportItem {
        ChatPhotoLibraryImportItem(
            suggestedName: suggestedName,
            canLoadImage: true,
            loadImage: { image }
        )
    }

    private func makeImporter(
        store: ChatAttachmentStore,
        jpegData: Data? = Data([0xCA, 0xFE])
    ) -> ChatAttachmentImporter {
        ChatAttachmentImporter(
            attachmentStore: store,
            filenames: ChatAttachmentImportFilenames(
                capturedPhotoFilename: { "captured-\($0).jpg" },
                photoLibraryImageFilename: { "library-\($0).jpg" }
            ),
            jpegData: { _, _ in jpegData }
        )
    }

    private func makeAttachmentStore() -> ChatAttachmentStore {
        ChatAttachmentStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ChatPhotoLibraryImportControllerTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func waitUntil(
        _ predicate: () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if predicate() {
                return
            }
            await Task.yield()
        }
    }
}
