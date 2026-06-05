//
//  ChatAttachmentThumbnailProviderTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatAttachmentThumbnailProviderTests: XCTestCase {
    func testStoreThumbnailCachesImageByAttachmentAndSize() {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let firstThumbnail = UIImage()
        let secondThumbnail = UIImage()
        let provider = Self.provider(scale: 1.0)

        provider.storeThumbnail(firstThumbnail, for: attachment, maxPointSize: 48.0)
        provider.storeThumbnail(secondThumbnail, for: attachment, maxPointSize: 110.0)

        XCTAssertTrue(provider.cachedThumbnail(for: attachment, maxPointSize: 48.0) === firstThumbnail)
        XCTAssertTrue(provider.cachedThumbnail(for: attachment, maxPointSize: 110.0) === secondThumbnail)
    }

    func testStoreThumbnailDoesNotCacheFileAttachment() {
        let attachment = Self.attachment(kind: .file, filename: "notes.pdf")
        let thumbnail = UIImage()
        let provider = Self.provider(scale: 1.0)

        provider.storeThumbnail(thumbnail, for: attachment, maxPointSize: 48.0)

        XCTAssertNil(provider.cachedThumbnail(for: attachment, maxPointSize: 48.0))
    }

    func testCacheKeyVariesByScale() {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let thumbnail = UIImage()
        let cache = ChatAttachmentThumbnailMemoryCache()
        let scaleOneProvider = Self.provider(cache: cache, scale: 1.0)
        let scaleTwoProvider = Self.provider(cache: cache, scale: 2.0)

        scaleOneProvider.storeThumbnail(thumbnail, for: attachment, maxPointSize: 48.0)

        XCTAssertTrue(scaleOneProvider.cachedThumbnail(for: attachment, maxPointSize: 48.0) === thumbnail)
        XCTAssertNil(scaleTwoProvider.cachedThumbnail(for: attachment, maxPointSize: 48.0))
    }

    func testCacheKeyVariesByRelativePath() {
        let firstAttachment = Self.attachment(kind: .image, filename: "first.png")
        let secondAttachment = ChatAttachment(
            assetID: firstAttachment.assetID,
            kind: .image,
            filename: "second.png",
            contentType: "image/png",
            relativePath: "second.png"
        )
        let thumbnail = UIImage()
        let provider = Self.provider(scale: 1.0)

        provider.storeThumbnail(thumbnail, for: firstAttachment, maxPointSize: 48.0)

        XCTAssertTrue(provider.cachedThumbnail(for: firstAttachment, maxPointSize: 48.0) === thumbnail)
        XCTAssertNil(provider.cachedThumbnail(for: secondAttachment, maxPointSize: 48.0))
    }

    func testRemoveCachedThumbnailsRemovesEverySizeAndScaleForAttachment() {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let otherAttachment = Self.attachment(kind: .image, filename: "other.png")
        let firstThumbnail = UIImage()
        let secondThumbnail = UIImage()
        let otherThumbnail = UIImage()
        let cache = ChatAttachmentThumbnailMemoryCache()
        let scaleOneProvider = Self.provider(cache: cache, scale: 1.0)
        let scaleTwoProvider = Self.provider(cache: cache, scale: 2.0)

        scaleOneProvider.storeThumbnail(firstThumbnail, for: attachment, maxPointSize: 48.0)
        scaleTwoProvider.storeThumbnail(secondThumbnail, for: attachment, maxPointSize: 110.0)
        scaleOneProvider.storeThumbnail(otherThumbnail, for: otherAttachment, maxPointSize: 48.0)

        scaleOneProvider.removeCachedThumbnails(for: attachment)

        XCTAssertNil(scaleOneProvider.cachedThumbnail(for: attachment, maxPointSize: 48.0))
        XCTAssertNil(scaleTwoProvider.cachedThumbnail(for: attachment, maxPointSize: 110.0))
        XCTAssertTrue(scaleOneProvider.cachedThumbnail(for: otherAttachment, maxPointSize: 48.0) === otherThumbnail)
    }

    func testRemoveAllCachedThumbnailsClearsTrackedKeys() {
        let attachment = Self.attachment(kind: .image, filename: "photo.png")
        let thumbnail = UIImage()
        let provider = Self.provider(scale: 1.0)

        provider.storeThumbnail(thumbnail, for: attachment, maxPointSize: 48.0)
        provider.removeAllCachedThumbnails()

        XCTAssertNil(provider.cachedThumbnail(for: attachment, maxPointSize: 48.0))
    }

    func testDownsampleReturnsNilForInvalidImageData() {
        XCTAssertNil(
            ChatAttachmentThumbnailProvider.downsampleImage(
                data: Data([0x00]),
                maxPointSize: 48.0,
                scale: 2.0
            )
        )
    }

    private static func provider(
        cache: ChatAttachmentThumbnailMemoryCache? = nil,
        scale: CGFloat
    ) -> ChatAttachmentThumbnailProvider {
        let cache = cache ?? ChatAttachmentThumbnailMemoryCache()
        return ChatAttachmentThumbnailProvider(
            cache: cache,
            scale: { scale }
        )
    }

    private static func attachment(
        kind: ChatAttachment.Kind,
        filename: String
    ) -> ChatAttachment {
        ChatAttachment(
            assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: kind,
            filename: filename,
            contentType: kind == .image ? "image/png" : "application/octet-stream",
            relativePath: filename
        )
    }
}
