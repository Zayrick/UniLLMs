//
//  ChatAttachmentAcquisitionWorkflow.swift
//  UniLLMs
//
//  Presents attachment pickers and imports selected attachment payloads.
//  Created by Codex on 2026/6/5.
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ChatAttachmentAcquisitionWorkflow: NSObject {
    typealias Source = ChatAttachmentAcquisitionSource

    typealias ImportedAttachmentsHandler = @MainActor ([ChatAttachment]) -> Void
    typealias ErrorPresenter = @MainActor (String) -> Void
    typealias ViewControllerPresenter = @MainActor (@escaping @MainActor () -> UIViewController) -> Void
    typealias ViewControllerDismisser = @MainActor (UIViewController) -> Void
    typealias CameraAvailability = @MainActor () -> Bool
    typealias CameraPickerBuilder = @MainActor (
        any UIImagePickerControllerDelegate & UINavigationControllerDelegate
    ) -> UIViewController
    typealias PhotoPickerBuilder = @MainActor (
        PHPickerConfiguration,
        any PHPickerViewControllerDelegate
    ) -> UIViewController
    typealias DocumentPickerBuilder = @MainActor (
        [UTType],
        Bool,
        Bool,
        any UIDocumentPickerDelegate
    ) -> UIViewController

    private let importController: ChatAttachmentImportController
    private let photoLibraryImportController: any ChatPhotoLibraryImportControlling
    private let acceptImportedAttachments: ImportedAttachmentsHandler
    private let presentError: ErrorPresenter
    private let presentViewController: ViewControllerPresenter
    private let dismissViewController: ViewControllerDismisser
    private let isCameraAvailable: CameraAvailability
    private let makeCameraPicker: CameraPickerBuilder
    private let makePhotoPicker: PhotoPickerBuilder
    private let makeDocumentPicker: DocumentPickerBuilder

    init(
        importController: ChatAttachmentImportController,
        photoLibraryImportController: any ChatPhotoLibraryImportControlling,
        acceptImportedAttachments: @escaping ImportedAttachmentsHandler,
        presentError: @escaping ErrorPresenter,
        presentViewController: @escaping ViewControllerPresenter,
        dismissViewController: @escaping ViewControllerDismisser = { viewController in
            viewController.dismiss(animated: true)
        },
        isCameraAvailable: @escaping CameraAvailability = {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        },
        makeCameraPicker: @escaping CameraPickerBuilder = { delegate in
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.allowsEditing = false
            picker.delegate = delegate
            return picker
        },
        makePhotoPicker: @escaping PhotoPickerBuilder = { configuration, delegate in
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = delegate
            return picker
        },
        makeDocumentPicker: @escaping DocumentPickerBuilder = { contentTypes, asCopy, allowsMultipleSelection, delegate in
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: contentTypes,
                asCopy: asCopy
            )
            picker.allowsMultipleSelection = allowsMultipleSelection
            picker.delegate = delegate
            return picker
        }
    ) {
        self.importController = importController
        self.photoLibraryImportController = photoLibraryImportController
        self.acceptImportedAttachments = acceptImportedAttachments
        self.presentError = presentError
        self.presentViewController = presentViewController
        self.dismissViewController = dismissViewController
        self.isCameraAvailable = isCameraAvailable
        self.makeCameraPicker = makeCameraPicker
        self.makePhotoPicker = makePhotoPicker
        self.makeDocumentPicker = makeDocumentPicker
        super.init()
    }

    func present(_ source: Source) {
        present(
            ChatAttachmentPickerPresentationPlan.make(
                source: source,
                isCameraAvailable: isCameraAvailable
            )
        )
    }

    func cancel() {
        photoLibraryImportController.cancel()
    }

    @discardableResult
    func importPhotoLibraryItems(_ items: [ChatPhotoLibraryImportItem]) -> Bool {
        photoLibraryImportController.importItems(items) { [weak self] result in
            self?.handleImportResult(result)
        }
    }

    private func present(_ plan: ChatAttachmentPickerPresentationPlan) {
        switch plan {
        case .cameraPicker:
            presentViewController { self.makeCameraPicker(self) }
        case let .photoLibraryPicker(configuration):
            presentViewController { self.makePhotoPicker(configuration, self) }
        case let .documentPicker(contentTypes, asCopy, allowsMultipleSelection):
            presentViewController {
                self.makeDocumentPicker(
                    contentTypes,
                    asCopy,
                    allowsMultipleSelection,
                    self
                )
            }
        case let .error(message):
            presentError(message)
        }
    }

    private func handleImportResult(_ result: ChatAttachmentImportResult) {
        acceptImportedAttachments(result.attachments)
        presentImportErrors(result.errors)
    }

    private func presentImportErrors(_ errors: [Error]) {
        if let presentation = ChatAttachmentImportErrorPresentation.make(for: errors) {
            presentError(presentation.message)
        }
    }
}

extension ChatAttachmentAcquisitionWorkflow: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        dismissViewController(picker)

        guard let image = info[.originalImage] as? UIImage else {
            return
        }

        handleImportResult(importController.importCapturedImage(image))
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismissViewController(picker)
    }
}

extension ChatAttachmentAcquisitionWorkflow: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismissViewController(picker)

        guard !results.isEmpty else {
            return
        }

        let items = results.map { result in
            ChatPhotoLibraryImportItem(itemProvider: result.itemProvider)
        }
        importPhotoLibraryItems(items)
    }
}

extension ChatAttachmentAcquisitionWorkflow: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        handleImportResult(importController.importDocuments(fromSecurityScopedURLs: urls))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        dismissViewController(controller)
    }
}
