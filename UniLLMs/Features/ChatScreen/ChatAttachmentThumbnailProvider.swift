//
//  ChatAttachmentThumbnailProvider.swift
//  UniLLMs
//
//  Loads, downsamples, and caches attachment thumbnail images.
//  Created by Codex on 2026/6/5.
//

import ImageIO
import UIKit

struct ChatAttachmentThumbnailCacheIdentity: Hashable {
    let assetID: UUID
    let relativePath: String

    init(attachment: ChatAttachment) {
        assetID = attachment.assetID
        relativePath = attachment.relativePath
    }
}

struct ChatAttachmentThumbnailCacheKey: Hashable {
    let identity: ChatAttachmentThumbnailCacheIdentity
    let maxPixelSize: Int
    let scaleHundredths: Int

    init(
        attachment: ChatAttachment,
        maxPointSize: CGFloat,
        scale: CGFloat
    ) {
        identity = ChatAttachmentThumbnailCacheIdentity(attachment: attachment)
        maxPixelSize = max(1, Int((maxPointSize * scale).rounded(.up)))
        scaleHundredths = max(1, Int((scale * 100.0).rounded()))
    }

    var storageKey: String {
        [
            identity.assetID.uuidString,
            identity.relativePath,
            String(maxPixelSize),
            String(scaleHundredths)
        ].joined(separator: "|")
    }
}

@MainActor
protocol ChatAttachmentThumbnailCaching: AnyObject {
    func image(for key: ChatAttachmentThumbnailCacheKey) -> UIImage?
    func store(_ image: UIImage, for key: ChatAttachmentThumbnailCacheKey)
    func removeImages(for identity: ChatAttachmentThumbnailCacheIdentity)
    func removeAll()
}

@MainActor
final class ChatAttachmentThumbnailMemoryCache: ChatAttachmentThumbnailCaching {
    static let shared = ChatAttachmentThumbnailMemoryCache()

    private let cache = NSCache<NSString, UIImage>()
    private var storageKeysByIdentity: [ChatAttachmentThumbnailCacheIdentity: Set<String>] = [:]

    init(countLimit: Int = 128) {
        cache.countLimit = countLimit
    }

    func image(for key: ChatAttachmentThumbnailCacheKey) -> UIImage? {
        guard let image = cache.object(forKey: key.storageKey as NSString) else {
            storageKeysByIdentity[key.identity]?.remove(key.storageKey)
            return nil
        }

        return image
    }

    func store(_ image: UIImage, for key: ChatAttachmentThumbnailCacheKey) {
        let pixelWidth = max(1, Int((image.size.width * image.scale).rounded(.up)))
        let pixelHeight = max(1, Int((image.size.height * image.scale).rounded(.up)))
        let storageKey = key.storageKey
        cache.setObject(
            image,
            forKey: storageKey as NSString,
            cost: pixelWidth * pixelHeight * 4
        )
        storageKeysByIdentity[key.identity, default: []].insert(storageKey)
    }

    func removeImages(for identity: ChatAttachmentThumbnailCacheIdentity) {
        guard let storageKeys = storageKeysByIdentity.removeValue(forKey: identity) else {
            return
        }

        for storageKey in storageKeys {
            cache.removeObject(forKey: storageKey as NSString)
        }
    }

    func removeAll() {
        cache.removeAllObjects()
        storageKeysByIdentity.removeAll()
    }
}

@MainActor
struct ChatAttachmentThumbnailProvider {
    typealias ScaleProvider = () -> CGFloat

    private let cache: (any ChatAttachmentThumbnailCaching)?
    private let scale: ScaleProvider

    init(
        scale: @escaping ScaleProvider = { 2.0 }
    ) {
        self.init(
            cache: ChatAttachmentThumbnailMemoryCache.shared,
            scale: scale
        )
    }

    init(
        cache: (any ChatAttachmentThumbnailCaching)?,
        scale: @escaping ScaleProvider
    ) {
        self.cache = cache
        self.scale = scale
    }

    func cachedThumbnail(
        for attachment: ChatAttachment,
        maxPointSize: CGFloat
    ) -> UIImage? {
        guard attachment.kind == .image else {
            return nil
        }

        return cache?.image(
            for: ChatAttachmentThumbnailCacheKey(
                attachment: attachment,
                maxPointSize: maxPointSize,
                scale: scale()
            )
        )
    }

    func storeThumbnail(
        _ image: UIImage,
        for attachment: ChatAttachment,
        maxPointSize: CGFloat
    ) {
        guard attachment.kind == .image else {
            return
        }

        cache?.store(
            image,
            for: ChatAttachmentThumbnailCacheKey(
                attachment: attachment,
                maxPointSize: maxPointSize,
                scale: scale()
            )
        )
    }

    func removeCachedThumbnails(for attachment: ChatAttachment) {
        guard attachment.kind == .image else {
            return
        }

        cache?.removeImages(for: ChatAttachmentThumbnailCacheIdentity(attachment: attachment))
    }

    func removeCachedThumbnails(for attachments: [ChatAttachment]) {
        for attachment in attachments {
            removeCachedThumbnails(for: attachment)
        }
    }

    func removeAllCachedThumbnails() {
        cache?.removeAll()
    }

    nonisolated static func downsampleImage(
        data: Data,
        maxPointSize: CGFloat,
        scale: CGFloat
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let maxPixelSize = max(1, Int((maxPointSize * scale).rounded(.up)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
