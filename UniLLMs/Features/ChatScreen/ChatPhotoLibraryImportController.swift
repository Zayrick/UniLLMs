//
//  ChatPhotoLibraryImportController.swift
//  UniLLMs
//
//  Owns asynchronous photo-library item loading and attachment import.
//  Created by Codex on 2026/6/5.
//

import UIKit

struct ChatPhotoLibraryImportItem {
    var suggestedName: String?
    var canLoadImage: Bool
    var loadImage: () async -> UIImage?
}

extension ChatPhotoLibraryImportItem {
    init(itemProvider: NSItemProvider) {
        suggestedName = itemProvider.suggestedName
        canLoadImage = itemProvider.canLoadObject(ofClass: UIImage.self)
        loadImage = {
            await withCheckedContinuation { continuation in
                itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}

@MainActor
protocol ChatPhotoLibraryImportControlling: AnyObject {
    @discardableResult
    func importItems(
        _ items: [ChatPhotoLibraryImportItem],
        didComplete: @escaping @MainActor (ChatAttachmentImportResult) -> Void
    ) -> Bool

    func cancel()
}

@MainActor
final class ChatPhotoLibraryImportController: ChatPhotoLibraryImportControlling {
    private let attachmentImporter: ChatAttachmentImporter
    private var importTask: Task<Void, Never>?
    private var generation = 0

    init(attachmentImporter: ChatAttachmentImporter) {
        self.attachmentImporter = attachmentImporter
    }

    func cancel() {
        generation += 1
        importTask?.cancel()
        importTask = nil
    }

    @discardableResult
    func importItems(
        _ items: [ChatPhotoLibraryImportItem],
        didComplete: @escaping @MainActor (ChatAttachmentImportResult) -> Void
    ) -> Bool {
        cancel()

        guard !items.isEmpty else {
            return false
        }

        let importGeneration = generation
        importTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            var attachments: [ChatAttachment] = []
            var importErrors: [Error] = []
            for (index, item) in items.enumerated() {
                guard !Task.isCancelled,
                      item.canLoadImage,
                      let image = await item.loadImage(),
                      !Task.isCancelled else {
                    continue
                }

                do {
                    let attachment = try attachmentImporter.importPhotoLibraryImage(
                        image,
                        suggestedName: item.suggestedName,
                        selectionNumber: index + 1
                    )
                    attachments.append(attachment)
                } catch {
                    importErrors.append(error)
                }
            }

            completeImport(
                generation: importGeneration,
                attachments: attachments,
                importErrors: importErrors,
                didComplete: didComplete
            )
        }
        return true
    }

    private func completeImport(
        generation importGeneration: Int,
        attachments: [ChatAttachment],
        importErrors: [Error],
        didComplete: @escaping @MainActor (ChatAttachmentImportResult) -> Void
    ) {
        guard importGeneration == generation,
              !Task.isCancelled else {
            return
        }

        importTask = nil
        didComplete(
            ChatAttachmentImportResult(
                attachments: attachments,
                errors: importErrors
            )
        )
    }
}
