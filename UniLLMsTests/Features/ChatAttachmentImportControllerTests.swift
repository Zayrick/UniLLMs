//
//  ChatAttachmentImportControllerTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

final class ChatAttachmentImportControllerTests: XCTestCase {
    func testCapturedImageReturnsAttachment() throws {
        let store = makeAttachmentStore()
        let controller = makeController(store: store, jpegData: Data([1, 2, 3]))

        let result = controller.importCapturedImage(UIImage())

        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.attachments.count, 1)
        XCTAssertEqual(result.attachments.first?.kind, .image)
        XCTAssertEqual(try store.loadData(for: result.attachments[0]), Data([1, 2, 3]))
    }

    func testCapturedImageEncodingFailureReturnsError() {
        let controller = makeController(store: makeAttachmentStore(), jpegData: nil)

        let result = controller.importCapturedImage(UIImage())

        XCTAssertTrue(result.attachments.isEmpty)
        XCTAssertEqual(result.errors.first as? ChatAttachmentImporterError, .imageEncodingFailed)
    }

    func testDocumentImportReturnsSuccessfulAttachmentsAndErrors() throws {
        let store = makeAttachmentStore()
        let controller = makeController(store: store, jpegData: Data([0]))
        let validURL = try writeTemporaryFile(filename: "notes.txt", data: Data([4, 5, 6]))
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: validURL)
        }

        let result = controller.importDocuments(fromSecurityScopedURLs: [validURL, missingURL])

        XCTAssertEqual(result.attachments.map(\.filename), ["notes.txt"])
        XCTAssertEqual(try store.loadData(for: result.attachments[0]), Data([4, 5, 6]))
        XCTAssertEqual(result.errors.count, 1)
    }

    func testEmptyDocumentImportReturnsEmptyResult() {
        let controller = makeController(store: makeAttachmentStore(), jpegData: Data([0]))

        let result = controller.importDocuments(fromSecurityScopedURLs: [])

        XCTAssertTrue(result.attachments.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
    }

    private func makeController(
        store: ChatAttachmentStore,
        jpegData: Data?
    ) -> ChatAttachmentImportController {
        ChatAttachmentImportController(
            attachmentImporter: ChatAttachmentImporter(
                attachmentStore: store,
                filenames: ChatAttachmentImportFilenames(
                    capturedPhotoFilename: { "captured-\($0).jpg" },
                    photoLibraryImageFilename: { "library-\($0).jpg" }
                ),
                jpegData: { _, _ in jpegData }
            )
        )
    }

    private func makeAttachmentStore() -> ChatAttachmentStore {
        ChatAttachmentStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ChatAttachmentImportControllerTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func writeTemporaryFile(filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentImportControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url)
        return url
    }
}
