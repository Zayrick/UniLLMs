//
//  ChatAttachmentImportController.swift
//  UniLLMs
//
//  Collects attachment import outcomes for picker delegates.
//  Created by Codex on 2026/6/5.
//

import UIKit

struct ChatAttachmentImportResult {
    var attachments: [ChatAttachment]
    var errors: [Error]

    static let empty = ChatAttachmentImportResult(attachments: [], errors: [])
}

struct ChatAttachmentImportController {
    private let attachmentImporter: ChatAttachmentImporter

    init(attachmentImporter: ChatAttachmentImporter) {
        self.attachmentImporter = attachmentImporter
    }

    func importCapturedImage(_ image: UIImage) -> ChatAttachmentImportResult {
        do {
            return ChatAttachmentImportResult(
                attachments: [try attachmentImporter.importCapturedImage(image)],
                errors: []
            )
        } catch {
            return ChatAttachmentImportResult(attachments: [], errors: [error])
        }
    }

    func importDocuments(fromSecurityScopedURLs urls: [URL]) -> ChatAttachmentImportResult {
        guard !urls.isEmpty else {
            return .empty
        }

        var attachments: [ChatAttachment] = []
        var errors: [Error] = []
        for url in urls {
            do {
                attachments.append(
                    try attachmentImporter.importDocument(fromSecurityScopedURL: url)
                )
            } catch {
                errors.append(error)
            }
        }

        return ChatAttachmentImportResult(attachments: attachments, errors: errors)
    }
}
