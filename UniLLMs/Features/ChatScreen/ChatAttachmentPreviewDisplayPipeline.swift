//
//  ChatAttachmentPreviewDisplayPipeline.swift
//  UniLLMs
//
//  Coordinates cached attachment preview displays with asynchronous thumbnail updates.
//  Created by Codex on 2026/6/5.
//

import Foundation
import UIKit

nonisolated protocol ChatAttachmentPreviewDisplayLoadTask: AnyObject {
    func cancel()
}

nonisolated struct ChatAttachmentThumbnailLoadResult: @unchecked Sendable {
    let attachmentID: UUID
    let thumbnailImage: UIImage?
}

@MainActor
protocol ChatAttachmentPreviewDisplayAsyncLoading {
    func loadThumbnails(
        for attachments: [ChatAttachment],
        thumbnailMaxPointSize: CGFloat,
        completion: @escaping @MainActor ([ChatAttachmentThumbnailLoadResult]) -> Void
    ) -> any ChatAttachmentPreviewDisplayLoadTask
}

@MainActor
final class ChatAttachmentPreviewDisplayPipeline {
    enum Scope: Hashable {
        case composer
        case message(UUID)
    }

    typealias UpdateHandler = @MainActor ([ChatAttachmentPreviewDisplay]) -> Void

    private struct ActiveLoad {
        var requestID: UUID
        var attachments: [ChatAttachment]
        var attachmentIDs: [UUID]
        var task: any ChatAttachmentPreviewDisplayLoadTask
    }

    private let displayBuilder: ChatAttachmentPreviewDisplayBuilder
    private let asyncLoader: any ChatAttachmentPreviewDisplayAsyncLoading
    private var activeLoads: [Scope: ActiveLoad] = [:]

    init(
        displayBuilder: ChatAttachmentPreviewDisplayBuilder,
        asyncLoader: any ChatAttachmentPreviewDisplayAsyncLoading
    ) {
        self.displayBuilder = displayBuilder
        self.asyncLoader = asyncLoader
    }

    func cancel(scope: Scope) {
        activeLoads.removeValue(forKey: scope)?.task.cancel()
    }

    func cancelAll() {
        activeLoads.values.forEach { $0.task.cancel() }
        activeLoads.removeAll()
    }

    func cancelMessageLoads() {
        for scope in Array(activeLoads.keys) {
            guard case .message = scope else {
                continue
            }

            cancel(scope: scope)
        }
    }

    @discardableResult
    func displays(
        for attachments: [ChatAttachment],
        thumbnailMaxPointSize: CGFloat,
        scope: Scope,
        didUpdate: @escaping UpdateHandler
    ) -> [ChatAttachmentPreviewDisplay] {
        cancel(scope: scope)

        let initialDisplays = displayBuilder.cachedDisplays(
            for: attachments,
            thumbnailMaxPointSize: thumbnailMaxPointSize
        )
        guard initialDisplays.contains(where: { $0.attachment.kind == .image && $0.thumbnailImage == nil }) else {
            return initialDisplays
        }

        let requestID = UUID()
        let attachmentIDs = attachments.map(\.id)
        let task = asyncLoader.loadThumbnails(
            for: attachments,
            thumbnailMaxPointSize: thumbnailMaxPointSize
        ) { [weak self] thumbnailResults in
            self?.completeLoad(
                requestID: requestID,
                scope: scope,
                thumbnailMaxPointSize: thumbnailMaxPointSize,
                thumbnailResults: thumbnailResults,
                didUpdate: didUpdate
            )
        }
        activeLoads[scope] = ActiveLoad(
            requestID: requestID,
            attachments: attachments,
            attachmentIDs: attachmentIDs,
            task: task
        )
        return initialDisplays
    }

    private func completeLoad(
        requestID: UUID,
        scope: Scope,
        thumbnailMaxPointSize: CGFloat,
        thumbnailResults: [ChatAttachmentThumbnailLoadResult],
        didUpdate: UpdateHandler
    ) {
        guard let activeLoad = activeLoads[scope],
              activeLoad.requestID == requestID,
              activeLoad.attachmentIDs == thumbnailResults.map(\.attachmentID) else {
            return
        }

        activeLoads.removeValue(forKey: scope)
        let loadedDisplays = zip(
            activeLoad.attachments,
            thumbnailResults
        ).map { attachment, result in
            ChatAttachmentPreviewDisplay(
                attachment: attachment,
                thumbnailImage: result.thumbnailImage
            )
        }
        for display in loadedDisplays {
            guard let thumbnailImage = display.thumbnailImage else {
                continue
            }

            displayBuilder.storeThumbnail(
                thumbnailImage,
                for: display.attachment,
                thumbnailMaxPointSize: thumbnailMaxPointSize
            )
        }
        didUpdate(loadedDisplays)
    }
}

struct ChatAttachmentAsyncThumbnailLoader: ChatAttachmentPreviewDisplayAsyncLoading {
    typealias FileURLProvider = (ChatAttachment) -> URL?
    typealias DataLoader = (URL) -> Data?
    typealias ImageDecoder = (Data, CGFloat, CGFloat) -> UIImage?
    typealias ScaleProvider = () -> CGFloat
    typealias Scheduler = (@escaping () -> Void) -> Void

    private let fileURL: FileURLProvider
    private let loadData: DataLoader
    private let decodeImage: ImageDecoder
    private let scale: ScaleProvider
    private let scheduleThumbnailLoad: Scheduler

    init(
        fileURL: @escaping FileURLProvider,
        loadData: @escaping DataLoader = { try? Data(contentsOf: $0) },
        decodeImage: @escaping ImageDecoder = ChatAttachmentThumbnailProvider.downsampleImage,
        scale: @escaping ScaleProvider = { 2.0 },
        scheduleThumbnailLoad: @escaping Scheduler = {
            DispatchQueue.global(qos: .userInitiated).async(execute: $0)
        }
    ) {
        self.fileURL = fileURL
        self.loadData = loadData
        self.decodeImage = decodeImage
        self.scale = scale
        self.scheduleThumbnailLoad = scheduleThumbnailLoad
    }

    func loadThumbnails(
        for attachments: [ChatAttachment],
        thumbnailMaxPointSize: CGFloat,
        completion: @escaping @MainActor ([ChatAttachmentThumbnailLoadResult]) -> Void
    ) -> any ChatAttachmentPreviewDisplayLoadTask {
        let task = ChatAttachmentPreviewDisplayWorkItem()
        let fileURL = fileURL
        let loadData = loadData
        let decodeImage = decodeImage
        let scale = scale()

        scheduleThumbnailLoad {
            guard !task.isCancelled else {
                return
            }

            let results = attachments.map { attachment in
                ChatAttachmentThumbnailLoadResult(
                    attachmentID: attachment.id,
                    thumbnailImage: Self.thumbnailImage(
                        for: attachment,
                        maxPointSize: thumbnailMaxPointSize,
                        scale: scale,
                        fileURL: fileURL,
                        loadData: loadData,
                        decodeImage: decodeImage
                    )
                )
            }
            guard !task.isCancelled else {
                return
            }

            Task { @MainActor in
                guard !task.isCancelled else {
                    return
                }

                completion(results)
            }
        }

        return task
    }

    nonisolated private static func thumbnailImage(
        for attachment: ChatAttachment,
        maxPointSize: CGFloat,
        scale: CGFloat,
        fileURL: FileURLProvider,
        loadData: DataLoader,
        decodeImage: ImageDecoder
    ) -> UIImage? {
        guard attachment.kind == .image,
              let url = fileURL(attachment),
              let data = loadData(url) else {
            return nil
        }

        return decodeImage(data, maxPointSize, scale)
    }
}

nonisolated final class ChatAttachmentPreviewDisplayWorkItem: ChatAttachmentPreviewDisplayLoadTask, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock {
            cancelled
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }
}
