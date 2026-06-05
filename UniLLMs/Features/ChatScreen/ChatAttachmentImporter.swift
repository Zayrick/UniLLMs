//
//  ChatAttachmentImporter.swift
//  UniLLMs
//
//  Converts user-selected images and documents into persisted chat attachments.
//  Created by Codex on 2026/6/5.
//

import UIKit
import UniformTypeIdentifiers

enum ChatAttachmentImporterError: LocalizedError, Equatable {
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return String(localized: .chatAttachmentPhotoEncodingFailed)
        }
    }
}

struct ChatAttachmentImportFilenames {
    var capturedPhotoFilename: (String) -> String
    var photoLibraryImageFilename: (Int) -> String

    static let localized = ChatAttachmentImportFilenames(
        capturedPhotoFilename: { timestamp in
            "\(String(localized: .chatAttachmentPhotoFilenameFormat(timestamp))).jpg"
        },
        photoLibraryImageFilename: { selectionNumber in
            "\(String(localized: .chatAttachmentImageFilenameFormat(selectionNumber))).jpg"
        }
    )
}

struct ChatAttachmentImporter {
    private let attachmentStore: ChatAttachmentStore
    private let now: () -> Date
    private let filenames: ChatAttachmentImportFilenames
    private let jpegData: (UIImage, CGFloat) -> Data?

    init(
        attachmentStore: ChatAttachmentStore,
        now: @escaping () -> Date = Date.init,
        filenames: ChatAttachmentImportFilenames = .localized,
        jpegData: @escaping (UIImage, CGFloat) -> Data? = { image, quality in
            image.jpegData(compressionQuality: quality)
        }
    ) {
        self.attachmentStore = attachmentStore
        self.now = now
        self.filenames = filenames
        self.jpegData = jpegData
    }

    func importCapturedImage(_ image: UIImage) throws -> ChatAttachment {
        let data = try encodedJPEGData(from: image)
        let timestamp = Self.timestampFilenameFormatter.string(from: now())
        return try attachmentStore.store(
            data: data,
            filename: filenames.capturedPhotoFilename(timestamp),
            kind: .image,
            contentType: "image/jpeg",
            preferredExtension: "jpg"
        )
    }

    func importPhotoLibraryImage(
        _ image: UIImage,
        suggestedName: String?,
        selectionNumber: Int
    ) throws -> ChatAttachment {
        let data = try encodedJPEGData(from: image)
        return try attachmentStore.store(
            data: data,
            filename: Self.suggestedPhotoFilename(suggestedName)
                ?? filenames.photoLibraryImageFilename(selectionNumber),
            kind: .image,
            contentType: "image/jpeg",
            preferredExtension: "jpg"
        )
    }

    func importDocument(fromSecurityScopedURL url: URL) throws -> ChatAttachment {
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try importDocument(from: url)
    }

    func importDocument(from url: URL) throws -> ChatAttachment {
        try attachmentStore.importFile(
            from: url,
            suggestedFilename: url.lastPathComponent,
            kind: Self.documentKind(for: url)
        )
    }

    static func documentKind(for url: URL) -> ChatAttachment.Kind {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) else {
            return .file
        }

        return .image
    }

    private func encodedJPEGData(from image: UIImage) throws -> Data {
        guard let data = jpegData(image, 0.9) else {
            throw ChatAttachmentImporterError.imageEncodingFailed
        }

        return data
    }

    private static func suggestedPhotoFilename(_ suggestedName: String?) -> String? {
        let trimmedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else {
            return nil
        }

        let baseName = (trimmedName as NSString).deletingPathExtension
        return "\((baseName.isEmpty ? trimmedName : baseName)).jpg"
    }

    private static let timestampFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
