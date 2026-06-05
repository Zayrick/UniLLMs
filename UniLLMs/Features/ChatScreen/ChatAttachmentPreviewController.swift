//
//  ChatAttachmentPreviewController.swift
//  UniLLMs
//
//  Prepares and owns the current Quick Look attachment preview item.
//  Created by Codex on 2026/6/5.
//

import QuickLook

enum ChatAttachmentPreviewPreparation: Equatable {
    case ready
    case fileMissing
    case previewUnavailable
}

final class ChatAttachmentPreviewController {
    private let fileURL: (ChatAttachment) -> URL?
    private let canPreview: @MainActor (AttachmentPreviewItem) -> Bool
    private var currentItem: AttachmentPreviewItem?

    init(
        fileURL: @escaping (ChatAttachment) -> URL?,
        canPreview: @escaping @MainActor (AttachmentPreviewItem) -> Bool = { QLPreviewController.canPreview($0) }
    ) {
        self.fileURL = fileURL
        self.canPreview = canPreview
    }

    var previewItemCount: Int {
        currentItem == nil ? 0 : 1
    }

    func preparePreview(for attachment: ChatAttachment) -> ChatAttachmentPreviewPreparation {
        guard let url = fileURL(attachment) else {
            currentItem = nil
            return .fileMissing
        }

        let item = AttachmentPreviewItem(url: url, title: attachment.filename)
        guard canPreview(item) else {
            currentItem = nil
            return .previewUnavailable
        }

        currentItem = item
        return .ready
    }

    func previewItem(at index: Int) -> any QLPreviewItem {
        guard index == 0,
              let currentItem else {
            fatalError("Attachment preview requested without a preview item.")
        }

        return currentItem
    }

    func clearPreview() {
        currentItem = nil
    }
}

final class AttachmentPreviewItem: NSObject, QLPreviewItem {
    private let url: URL
    private let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        super.init()
    }

    var previewItemURL: URL? {
        url
    }

    var previewItemTitle: String? {
        title
    }
}
