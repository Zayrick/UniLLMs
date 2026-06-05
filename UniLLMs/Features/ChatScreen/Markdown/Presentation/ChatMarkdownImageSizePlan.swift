//
//  ChatMarkdownImageSizePlan.swift
//  UniLLMs
//
//  Plans Markdown image view dimensions for loaded and placeholder states.
//

import CoreGraphics

nonisolated struct ChatMarkdownImageSizePlan {
    static let defaultPlaceholderHeight: CGFloat = 150.0
    static let defaultMaxImageHeight: CGFloat = 400.0

    var size: CGSize

    nonisolated init(
        imageSize: CGSize?,
        maxWidth: CGFloat,
        placeholderHeight: CGFloat = Self.defaultPlaceholderHeight,
        maxImageHeight: CGFloat = Self.defaultMaxImageHeight
    ) {
        let effectiveMaxWidth = max(1.0, maxWidth)
        guard let imageSize,
              imageSize.width > 0.0,
              imageSize.height > 0.0 else {
            size = CGSize(
                width: effectiveMaxWidth,
                height: placeholderHeight
            )
            return
        }

        let aspectRatio = imageSize.width / imageSize.height
        var targetWidth = min(imageSize.width, effectiveMaxWidth)
        var targetHeight = targetWidth / aspectRatio

        if targetHeight > maxImageHeight {
            targetHeight = maxImageHeight
            targetWidth = targetHeight * aspectRatio
        }

        size = CGSize(
            width: ceil(max(1.0, targetWidth)),
            height: ceil(max(1.0, targetHeight))
        )
    }
}
