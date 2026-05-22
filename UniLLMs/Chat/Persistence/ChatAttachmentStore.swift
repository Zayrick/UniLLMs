//
//  ChatAttachmentStore.swift
//  UniLLMs
//
//  Persists chat attachment payloads (images and files) to a managed app
//  support directory. Timelines store lightweight `ChatAttachment` references
//  whose instance identity is separate from the on-disk file asset identity.
//
//  Created by Zayrick on 2026/5/17.
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
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.rootDirectory = applicationSupport
                .appendingPathComponent("UniLLMs", isDirectory: true)
                .appendingPathComponent("ChatAttachments", isDirectory: true)
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
    /// `ChatAttachment` reference. Each call creates a distinct attachment
    /// instance and a distinct on-disk file asset.
    @discardableResult
    func store(
        data: Data,
        filename: String,
        kind: ChatAttachment.Kind,
        contentType: String,
        preferredExtension: String? = nil
    ) throws -> ChatAttachment {
        let resolvedContentType = contentType.isEmpty ? "application/octet-stream" : contentType

        lock.lock()
        defer { lock.unlock() }

        try ensureRootDirectoryExists()
        let attachmentID = UUID()
        let assetID = UUID()
        let resolvedExtension = (preferredExtension?.isEmpty == false
            ? preferredExtension
            : Self.preferredExtension(forMIMEType: resolvedContentType)) ?? "bin"
        let storedFilename = "\(assetID.uuidString).\(resolvedExtension)"
        let destination = rootDirectory.appendingPathComponent(storedFilename)
        try data.write(to: destination, options: .atomic)

        return ChatAttachment(
            id: attachmentID,
            assetID: assetID,
            kind: kind,
            filename: filename,
            contentType: resolvedContentType,
            relativePath: storedFilename
        )
    }

    func fileURL(for attachment: ChatAttachment) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        guard let url = storedURL(for: attachment) else {
            return nil
        }
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func loadData(for attachment: ChatAttachment) throws -> Data {
        guard let url = fileURL(for: attachment) else {
            throw ChatAttachmentStoreError.fileNotFound
        }

        return try Data(contentsOf: url)
    }

    func deleteUnreferencedAttachments(
        removing removedAttachments: [ChatAttachment],
        referencedBy retainedAttachments: [ChatAttachment]
    ) throws {
        guard !removedAttachments.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let retainedAssetIDs = Set(retainedAttachments.map(\.assetID))
        var deletedAssetIDs = Set<UUID>()

        for attachment in removedAttachments where !retainedAssetIDs.contains(attachment.assetID) {
            guard let url = storedURL(for: attachment),
                  fileManager.fileExists(atPath: url.path) else {
                continue
            }
            guard deletedAssetIDs.insert(attachment.assetID).inserted else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
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

    private func ensureRootDirectoryExists() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    private func storedURL(for attachment: ChatAttachment) -> URL? {
        guard Self.isStoredRelativePath(attachment.relativePath) else {
            return nil
        }
        return rootDirectory.appendingPathComponent(attachment.relativePath, isDirectory: false)
    }

    private static func isStoredRelativePath(_ relativePath: String) -> Bool {
        !relativePath.isEmpty && relativePath == (relativePath as NSString).lastPathComponent
    }
}
