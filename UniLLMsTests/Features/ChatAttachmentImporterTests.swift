//
//  ChatAttachmentImporterTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

final class ChatAttachmentImporterTests: XCTestCase {
    func testCapturedImageUsesTimestampedJpegAttachment() throws {
        let store = makeAttachmentStore()
        var capturedTimestamp = ""
        let importer = makeImporter(
            store: store,
            now: Date(timeIntervalSince1970: 1_781_234_567),
            jpegData: Data([1, 2, 3]),
            capturedPhotoFilename: { timestamp in
                capturedTimestamp = timestamp
                return "captured.jpg"
            }
        )

        let attachment = try importer.importCapturedImage(UIImage())

        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.filename, "captured.jpg")
        XCTAssertFalse(capturedTimestamp.isEmpty)
        XCTAssertEqual(attachment.contentType, "image/jpeg")
        XCTAssertEqual(try store.loadData(for: attachment), Data([1, 2, 3]))
    }

    func testPhotoLibraryImageUsesTrimmedSuggestedName() throws {
        let store = makeAttachmentStore()
        let importer = makeImporter(store: store, jpegData: Data([4, 5, 6]))

        let attachment = try importer.importPhotoLibraryImage(
            UIImage(),
            suggestedName: " IMG_0001 ",
            selectionNumber: 4
        )

        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.filename, "IMG_0001.jpg")
        XCTAssertEqual(try store.loadData(for: attachment), Data([4, 5, 6]))
    }

    func testPhotoLibraryImageReplacesSuggestedNameExtensionWithJpegExtension() throws {
        let store = makeAttachmentStore()
        let importer = makeImporter(store: store, jpegData: Data([4, 5, 6]))

        let attachment = try importer.importPhotoLibraryImage(
            UIImage(),
            suggestedName: " IMG_0001.PNG ",
            selectionNumber: 4
        )

        XCTAssertEqual(attachment.filename, "IMG_0001.jpg")
        XCTAssertEqual(attachment.contentType, "image/jpeg")
    }

    func testPhotoLibraryImageUsesFallbackSelectionNumber() throws {
        let store = makeAttachmentStore()
        let importer = makeImporter(store: store, jpegData: Data([7]))

        let attachment = try importer.importPhotoLibraryImage(
            UIImage(),
            suggestedName: " ",
            selectionNumber: 2
        )

        XCTAssertEqual(attachment.filename, "library-2.jpg")
    }

    func testImageEncodingFailureThrowsImporterError() {
        let importer = makeImporter(store: makeAttachmentStore(), jpegData: nil)

        XCTAssertThrowsError(
            try importer.importCapturedImage(UIImage())
        ) { error in
            XCTAssertEqual(error as? ChatAttachmentImporterError, .imageEncodingFailed)
        }
    }

    func testDocumentKindUsesFilenameType() {
        XCTAssertEqual(
            ChatAttachmentImporter.documentKind(for: URL(fileURLWithPath: "/tmp/photo.png")),
            .image
        )
        XCTAssertEqual(
            ChatAttachmentImporter.documentKind(for: URL(fileURLWithPath: "/tmp/archive.bin")),
            .file
        )
    }

    func testDocumentImportStoresImageAndFileAttachments() throws {
        let store = makeAttachmentStore()
        let importer = makeImporter(store: store, jpegData: Data([0]))
        let imageURL = try writeTemporaryFile(filename: "photo.png", data: Data([8, 9]))
        let fileURL = try writeTemporaryFile(filename: "notes.txt", data: Data([10, 11]))
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let imageAttachment = try importer.importDocument(from: imageURL)
        let fileAttachment = try importer.importDocument(from: fileURL)

        XCTAssertEqual(imageAttachment.kind, .image)
        XCTAssertEqual(imageAttachment.filename, "photo.png")
        XCTAssertEqual(try store.loadData(for: imageAttachment), Data([8, 9]))
        XCTAssertEqual(fileAttachment.kind, .file)
        XCTAssertEqual(fileAttachment.filename, "notes.txt")
        XCTAssertEqual(try store.loadData(for: fileAttachment), Data([10, 11]))
    }

    private func makeImporter(
        store: ChatAttachmentStore,
        now: Date = Date(timeIntervalSince1970: 0),
        jpegData: Data?,
        capturedPhotoFilename: @escaping (String) -> String = { "captured-\($0).jpg" },
        photoLibraryImageFilename: @escaping (Int) -> String = { "library-\($0).jpg" }
    ) -> ChatAttachmentImporter {
        ChatAttachmentImporter(
            attachmentStore: store,
            now: { now },
            filenames: ChatAttachmentImportFilenames(
                capturedPhotoFilename: capturedPhotoFilename,
                photoLibraryImageFilename: photoLibraryImageFilename
            ),
            jpegData: { _, _ in jpegData }
        )
    }

    private func makeAttachmentStore() -> ChatAttachmentStore {
        ChatAttachmentStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ChatAttachmentImporterTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func writeTemporaryFile(filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url)
        return url
    }
}
