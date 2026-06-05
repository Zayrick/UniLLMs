//
//  ChatAttachmentPreviewDisplayTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatAttachmentPreviewDisplayTests: XCTestCase {
    func testCachedDisplaysReturnPlaceholdersWhenCacheIsEmpty() {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let builder = Self.makeBuilder()

        let displays = builder.cachedDisplays(for: [attachment])

        XCTAssertEqual(displays.map(\.attachment), [attachment])
        XCTAssertNil(displays.first?.thumbnailImage)
    }

    func testCachedDisplaysReturnStoredThumbnail() {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let thumbnail = UIImage()
        let builder = Self.makeBuilder(thumbnailMaxPointSize: 48.0)

        builder.storeThumbnail(thumbnail, for: attachment)

        let displays = builder.cachedDisplays(for: [attachment])
        XCTAssertTrue(displays.first?.thumbnailImage === thumbnail)
    }

    func testFileAttachmentCachedDisplayDoesNotUseThumbnail() {
        let attachment = Self.attachment(kind: .file, filename: "notes.pdf")
        let thumbnail = UIImage()
        let builder = Self.makeBuilder(thumbnailMaxPointSize: 48.0)

        builder.storeThumbnail(thumbnail, for: attachment)

        let displays = builder.cachedDisplays(for: [attachment])
        XCTAssertEqual(displays.map(\.attachment), [attachment])
        XCTAssertNil(displays.first?.thumbnailImage)
    }

    func testDisplayExposesAttachmentDerivedProperties() {
        let attachment = Self.attachment(kind: .file, filename: "notes.pdf")
        let display = ChatAttachmentPreviewDisplay(attachment: attachment, thumbnailImage: nil)

        XCTAssertEqual(display.id, attachment.id)
        XCTAssertEqual(display.filename, "notes.pdf")
        XCTAssertTrue(display.isFile)
    }

    func testPlaceholderDisplaysPreserveAttachmentsInOrderWithoutImageData() {
        let first = Self.attachment(kind: .image, filename: "first.png")
        let second = Self.attachment(kind: .file, filename: "second.pdf")

        let displays = ChatAttachmentPreviewDisplay.placeholders(for: [first, second])

        XCTAssertEqual(displays.map(\.attachment), [first, second])
        XCTAssertTrue(displays.allSatisfy { $0.thumbnailImage == nil })
    }

    private static func makeBuilder(
        thumbnailMaxPointSize: CGFloat = 110.0,
        scale: CGFloat = 1.0
    ) -> ChatAttachmentPreviewDisplayBuilder {
        ChatAttachmentPreviewDisplayBuilder(
            thumbnailProvider: ChatAttachmentThumbnailProvider(
                cache: ChatAttachmentThumbnailMemoryCache(),
                scale: { scale }
            ),
            thumbnailMaxPointSize: thumbnailMaxPointSize
        )
    }

    private static func attachment(
        kind: ChatAttachment.Kind,
        filename: String
    ) -> ChatAttachment {
        ChatAttachment(
            kind: kind,
            filename: filename,
            contentType: kind == .image ? "image/png" : "application/octet-stream",
            relativePath: filename
        )
    }
}
