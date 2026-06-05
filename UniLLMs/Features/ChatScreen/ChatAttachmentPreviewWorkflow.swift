//
//  ChatAttachmentPreviewWorkflow.swift
//  UniLLMs
//
//  Owns attachment Quick Look presentation and preview lifecycle.
//  Created by Codex on 2026/6/5.
//

import QuickLook
import UIKit

@MainActor
final class ChatAttachmentPreviewWorkflow: NSObject {
    typealias ModalPresentationState = @MainActor () -> Bool
    typealias EndEditing = @MainActor () -> Void
    typealias ViewControllerPresenter = @MainActor (UIViewController) -> Void
    typealias ErrorPresenter = @MainActor (String) -> Void
    typealias PreviewControllerBuilder = @MainActor () -> QLPreviewController

    private let previewController: ChatAttachmentPreviewController
    private let isPresentingModal: ModalPresentationState
    private let endEditing: EndEditing
    private let presentViewController: ViewControllerPresenter
    private let presentError: ErrorPresenter
    private let makePreviewController: PreviewControllerBuilder

    init(
        previewController: ChatAttachmentPreviewController,
        isPresentingModal: @escaping ModalPresentationState,
        endEditing: @escaping EndEditing,
        presentViewController: @escaping ViewControllerPresenter,
        presentError: @escaping ErrorPresenter,
        makePreviewController: @escaping PreviewControllerBuilder = { QLPreviewController() }
    ) {
        self.previewController = previewController
        self.isPresentingModal = isPresentingModal
        self.endEditing = endEditing
        self.presentViewController = presentViewController
        self.presentError = presentError
        self.makePreviewController = makePreviewController
        super.init()
    }

    func presentPreview(for attachment: ChatAttachment) {
        guard !isPresentingModal() else {
            return
        }

        switch previewController.preparePreview(for: attachment) {
        case .ready:
            break
        case .fileMissing:
            presentError(String(localized: .chatAttachmentFileMissing))
            return
        case .previewUnavailable:
            presentError(String(localized: .chatAttachmentPreviewUnavailable))
            return
        }

        endEditing()

        let quickLookController = makePreviewController()
        quickLookController.dataSource = self
        quickLookController.delegate = self
        quickLookController.currentPreviewItemIndex = 0
        presentViewController(quickLookController)
    }
}

extension ChatAttachmentPreviewWorkflow: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewController.previewItemCount
    }

    func previewController(
        _ controller: QLPreviewController,
        previewItemAt index: Int
    ) -> any QLPreviewItem {
        previewController.previewItem(at: index)
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        previewController.clearPreview()
    }
}
