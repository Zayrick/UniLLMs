//
//  ChatAttachmentPreviewDisplay.swift
//  UniLLMs
//
//  Builds attachment preview display data from chat attachments.
//  Created by Codex on 2026/6/5.
//

import UIKit

struct ChatAttachmentPreviewDisplay: Equatable {
    let attachment: ChatAttachment
    let thumbnailImage: UIImage?

    var id: UUID {
        attachment.id
    }

    var filename: String {
        attachment.filename
    }

    var isFile: Bool {
        attachment.kind == .file
    }

    static func placeholders(for attachments: [ChatAttachment]) -> [ChatAttachmentPreviewDisplay] {
        attachments.map {
            ChatAttachmentPreviewDisplay(attachment: $0, thumbnailImage: nil)
        }
    }
}

@MainActor
struct ChatAttachmentPreviewDisplayBuilder {
    var thumbnailProvider: ChatAttachmentThumbnailProvider
    var thumbnailMaxPointSize: CGFloat

    init(
        thumbnailMaxPointSize: CGFloat = 110.0
    ) {
        thumbnailProvider = ChatAttachmentThumbnailProvider()
        self.thumbnailMaxPointSize = thumbnailMaxPointSize
    }

    init(
        thumbnailProvider: ChatAttachmentThumbnailProvider,
        thumbnailMaxPointSize: CGFloat = 110.0
    ) {
        self.thumbnailProvider = thumbnailProvider
        self.thumbnailMaxPointSize = thumbnailMaxPointSize
    }

    func cachedDisplays(
        for attachments: [ChatAttachment],
        thumbnailMaxPointSize: CGFloat? = nil
    ) -> [ChatAttachmentPreviewDisplay] {
        let thumbnailMaxPointSize = thumbnailMaxPointSize ?? self.thumbnailMaxPointSize
        return attachments.map { attachment in
            ChatAttachmentPreviewDisplay(
                attachment: attachment,
                thumbnailImage: thumbnailProvider.cachedThumbnail(
                    for: attachment,
                    maxPointSize: thumbnailMaxPointSize
                )
            )
        }
    }

    func storeThumbnail(
        _ image: UIImage,
        for attachment: ChatAttachment,
        thumbnailMaxPointSize: CGFloat? = nil
    ) {
        thumbnailProvider.storeThumbnail(
            image,
            for: attachment,
            maxPointSize: thumbnailMaxPointSize ?? self.thumbnailMaxPointSize
        )
    }
}
