//
//  ChatAttachmentStoreTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatAttachmentStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testRootDirectoryResolutionFallbackReportsFailureAndStoresInFallbackDirectory() throws {
        let fallbackRootDirectory = makeTemporaryDirectoryURL()
        var failures: [ChatAttachmentStoreFailure] = []
        let store = ChatAttachmentStore(
            rootDirectoryResolver: FallbackRootDirectoryResolver(fallbackRootDirectory: fallbackRootDirectory)
        ) { failure in
            failures.append(failure)
        }

        let attachment = try store.store(
            data: Data("payload".utf8),
            filename: "fallback.txt",
            kind: .file,
            contentType: "text/plain",
            preferredExtension: "txt"
        )

        let storedURL = try XCTUnwrap(store.fileURL(for: attachment))
        XCTAssertTrue(storedURL.path.hasPrefix(fallbackRootDirectory.path))
        XCTAssertEqual(failures.count, 1)
        guard case let .rootDirectoryFallback(reportedFallback, _) = failures.first else {
            XCTFail("Expected root directory fallback failure.")
            return
        }
        XCTAssertEqual(reportedFallback, fallbackRootDirectory)
    }

    func testInitialRootDirectoryCreationFailureIsReported() throws {
        let parentDirectory = makeTemporaryDirectoryURL()
        try FileManager.default.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true
        )
        let rootFileURL = parentDirectory
            .appendingPathComponent("AttachmentRoot", isDirectory: false)
        try Data("not a directory".utf8).write(to: rootFileURL)
        var failures: [ChatAttachmentStoreFailure] = []

        let store = ChatAttachmentStore(rootDirectory: rootFileURL) { failure in
            failures.append(failure)
        }

        XCTAssertEqual(failures.count, 1)
        guard case let .initialDirectoryCreationFailed(reportedRootDirectory, _) = failures.first else {
            XCTFail("Expected initial directory creation failure.")
            return
        }
        XCTAssertEqual(reportedRootDirectory, rootFileURL)
        XCTAssertThrowsError(
            try store.store(
                data: Data("payload".utf8),
                filename: "blocked.txt",
                kind: .file,
                contentType: "text/plain",
                preferredExtension: "txt"
            )
        )
    }

    func testDeleteUnreferencedAttachmentsReturnsOnlyUnreferencedUniqueAssets() throws {
        let rootDirectory = makeTemporaryDirectoryURL()
        let store = ChatAttachmentStore(rootDirectory: rootDirectory)
        let removedAttachment = try store.store(
            data: Data("remove".utf8),
            filename: "remove.jpg",
            kind: .image,
            contentType: "image/jpeg",
            preferredExtension: "jpg"
        )
        var duplicateRemovedReference = removedAttachment
        duplicateRemovedReference.id = UUID()
        let retainedAttachment = try store.store(
            data: Data("retain".utf8),
            filename: "retain.jpg",
            kind: .image,
            contentType: "image/jpeg",
            preferredExtension: "jpg"
        )
        var retainedReference = retainedAttachment
        retainedReference.id = UUID()

        let result = try store.deleteUnreferencedAttachments(
            removing: [
                removedAttachment,
                duplicateRemovedReference,
                retainedAttachment
            ],
            referencedBy: [retainedReference]
        )

        XCTAssertEqual(result, ChatAttachmentCleanupResult(removedUnreferencedAttachments: [removedAttachment]))
        XCTAssertNil(store.fileURL(for: removedAttachment))
        XCTAssertNotNil(store.fileURL(for: retainedAttachment))
    }

    private func makeTemporaryDirectoryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentStoreTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

private struct FallbackRootDirectoryResolver: ChatAttachmentRootDirectoryResolving {
    var fallbackRootDirectory: URL

    func rootDirectory(fileManager: FileManager) -> ChatAttachmentRootDirectoryResolution {
        ChatAttachmentRootDirectoryResolution(
            rootDirectory: fallbackRootDirectory,
            failure: .rootDirectoryFallback(
                fallbackRootDirectory: fallbackRootDirectory,
                underlyingError: RootDirectoryResolutionFailure.sample
            )
        )
    }
}

private enum RootDirectoryResolutionFailure: Error {
    case sample
}
