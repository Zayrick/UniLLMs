//
//  ChatAttachmentStore.swift
//  UniLLMs
//
//  Persists chat attachment payloads (images and files) to a managed directory
//  inside the app's Documents folder. The directory layout keeps each
//  attachment under its own UUID-derived filename so the timeline only needs
//  to persist a stable relative path next to the original filename and MIME
//  type. The store is intentionally tiny: it only owns the on-disk bytes.
//  Metadata lives in `ChatAttachment`.
//
//  Created by Codex on 2026/5/17.
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum ChatAttachmentStoreError: LocalizedError, Equatable {
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The attachment file is missing on disk."
        }
    }
}

nonisolated final class ChatAttachmentStore: @unchecked Sendable {
    static let shared = ChatAttachmentStore()

    private let fileManager: FileManager
    private let rootDirectory: URL

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let documents = (try? fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.rootDirectory = documents.appendingPathComponent("ChatAttachments", isDirectory: true)
        }

        try? fileManager.createDirectory(
            at: self.rootDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Copies the given file URL into the managed directory.
    /// The original `sourceURL` is read once and written under a UUID-derived
    /// filename. If the read requires a security scope (e.g. from
    /// `UIDocumentPickerViewController`), the caller is responsible for
    /// starting/stopping the scope around this call.
    @discardableResult
    func importFile(
        from sourceURL: URL,
        suggestedFilename: String? = nil,
        kind: ChatAttachment.Kind,
        contentType: String? = nil
    ) throws -> ChatAttachment {
        let data = try Data(contentsOf: sourceURL)
        let filename = suggestedFilename
            ?? sourceURL.lastPathComponent
        let resolvedContentType = contentType
            ?? Self.mimeType(forFilename: filename)
            ?? "application/octet-stream"
        return try store(
            data: data,
            filename: filename,
            kind: kind,
            contentType: resolvedContentType,
            preferredExtension: (filename as NSString).pathExtension.isEmpty
                ? sourceURL.pathExtension
                : (filename as NSString).pathExtension
        )
    }

    /// Writes raw bytes to the managed directory and returns the matching
    /// `ChatAttachment` metadata. Used for camera-captured images that don't
    /// originate from a file URL.
    @discardableResult
    func store(
        data: Data,
        filename: String,
        kind: ChatAttachment.Kind,
        contentType: String,
        preferredExtension: String? = nil
    ) throws -> ChatAttachment {
        let attachmentID = UUID()
        let resolvedExtension = (preferredExtension?.isEmpty == false
            ? preferredExtension
            : Self.preferredExtension(forMIMEType: contentType)) ?? "bin"
        let relativePath = "\(attachmentID.uuidString).\(resolvedExtension)"
        let destination = rootDirectory.appendingPathComponent(relativePath)
        try data.write(to: destination, options: .atomic)
        return ChatAttachment(
            id: attachmentID,
            kind: kind,
            filename: filename,
            contentType: contentType,
            relativePath: relativePath
        )
    }

    func fileURL(for attachment: ChatAttachment) -> URL? {
        guard let relativePath = attachment.relativePath,
              !relativePath.isEmpty else {
            return nil
        }

        let url = rootDirectory.appendingPathComponent(relativePath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func loadData(for attachment: ChatAttachment) throws -> Data {
        guard let url = fileURL(for: attachment) else {
            throw ChatAttachmentStoreError.fileNotFound
        }

        return try Data(contentsOf: url)
    }

    static func mimeType(forFilename filename: String) -> String? {
        let ext = (filename as NSString).pathExtension
        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext),
              let mime = type.preferredMIMEType else {
            return nil
        }
        return mime
    }

    static func preferredExtension(forMIMEType mimeType: String) -> String? {
        guard let type = UTType(mimeType: mimeType),
              let ext = type.preferredFilenameExtension else {
            return nil
        }
        return ext
    }
}
