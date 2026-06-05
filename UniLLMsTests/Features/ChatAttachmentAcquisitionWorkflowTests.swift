//
//  ChatAttachmentAcquisitionWorkflowTests.swift
//  UniLLMsTests
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import UniLLMs

@MainActor
final class ChatAttachmentAcquisitionWorkflowTests: XCTestCase {
    private var rootDirectory: URL!
    private var attachmentStore: ChatAttachmentStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentAcquisitionWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        attachmentStore = ChatAttachmentStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        attachmentStore = nil
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testPresentCameraBuildsPickerWhenAvailable() {
        let expectedPicker = UIViewController()
        var presentedViewController: UIViewController?
        var capturedDelegate: (any UIImagePickerControllerDelegate & UINavigationControllerDelegate)?
        let workflow = makeWorkflow(
            presentViewController: { makeViewController in
                presentedViewController = makeViewController()
            },
            isCameraAvailable: { true },
            makeCameraPicker: { delegate in
                capturedDelegate = delegate
                return expectedPicker
            }
        )

        workflow.present(.camera)

        XCTAssertTrue(presentedViewController === expectedPicker)
        XCTAssertTrue((capturedDelegate as AnyObject?) === workflow)
    }

    func testPresentCameraReportsUnavailableWithoutBuildingPicker() {
        var presentedErrors: [String] = []
        var didBuildPicker = false
        let workflow = makeWorkflow(
            presentError: {
                presentedErrors.append($0)
            },
            isCameraAvailable: { false },
            makeCameraPicker: { _ in
                didBuildPicker = true
                return UIViewController()
            }
        )

        workflow.present(.camera)

        XCTAssertFalse(didBuildPicker)
        XCTAssertEqual(presentedErrors, [String(localized: .chatAttachmentCameraUnavailable)])
    }

    func testPresentCameraDefersPickerConstructionToPresenter() {
        var didBuildPicker = false
        var didAskPresenter = false
        let workflow = makeWorkflow(
            presentViewController: { _ in
                didAskPresenter = true
            },
            isCameraAvailable: { true },
            makeCameraPicker: { _ in
                didBuildPicker = true
                return UIViewController()
            }
        )

        workflow.present(.camera)

        XCTAssertTrue(didAskPresenter)
        XCTAssertFalse(didBuildPicker)
    }

    func testPresentPhotoLibraryBuildsImageConfiguration() {
        let expectedPicker = UIViewController()
        var presentedViewController: UIViewController?
        var capturedConfiguration: PHPickerConfiguration?
        var capturedDelegate: (any PHPickerViewControllerDelegate)?
        let workflow = makeWorkflow(
            presentViewController: { makeViewController in
                presentedViewController = makeViewController()
            },
            makePhotoPicker: { configuration, delegate in
                capturedConfiguration = configuration
                capturedDelegate = delegate
                return expectedPicker
            }
        )

        workflow.present(.photoLibrary)

        XCTAssertTrue(presentedViewController === expectedPicker)
        XCTAssertEqual(capturedConfiguration?.selectionLimit, 0)
        XCTAssertNotNil(capturedConfiguration?.filter)
        XCTAssertEqual(capturedConfiguration?.preferredAssetRepresentationMode, .current)
        XCTAssertTrue((capturedDelegate as AnyObject?) === workflow)
    }

    func testPresentDocumentsBuildsItemCopyPicker() {
        let expectedPicker = UIViewController()
        var presentedViewController: UIViewController?
        var capturedContentTypes: [UTType] = []
        var capturedAsCopy = false
        var capturedAllowsMultipleSelection = false
        var capturedDelegate: (any UIDocumentPickerDelegate)?
        let workflow = makeWorkflow(
            presentViewController: { makeViewController in
                presentedViewController = makeViewController()
            },
            makeDocumentPicker: { contentTypes, asCopy, allowsMultipleSelection, delegate in
                capturedContentTypes = contentTypes
                capturedAsCopy = asCopy
                capturedAllowsMultipleSelection = allowsMultipleSelection
                capturedDelegate = delegate
                return expectedPicker
            }
        )

        workflow.present(.documents)

        XCTAssertTrue(presentedViewController === expectedPicker)
        XCTAssertEqual(capturedContentTypes, [.item])
        XCTAssertTrue(capturedAsCopy)
        XCTAssertTrue(capturedAllowsMultipleSelection)
        XCTAssertTrue((capturedDelegate as AnyObject?) === workflow)
    }

    func testCameraFinishDismissesAndImportsCapturedImage() throws {
        var acceptedAttachments: [ChatAttachment] = []
        var dismissedViewControllers: [UIViewController] = []
        let workflow = makeWorkflow(
            acceptImportedAttachments: {
                acceptedAttachments.append(contentsOf: $0)
            },
            dismissViewController: {
                dismissedViewControllers.append($0)
            }
        )
        let picker = UIImagePickerController()

        workflow.imagePickerController(
            picker,
            didFinishPickingMediaWithInfo: [.originalImage: UIImage()]
        )

        XCTAssertEqual(dismissedViewControllers, [picker])
        XCTAssertEqual(acceptedAttachments.map(\.filename), ["captured-1.jpg"])
        XCTAssertEqual(try attachmentStore.loadData(for: acceptedAttachments[0]), Data([0xCA, 0xFE]))
    }

    func testCameraFinishWithMissingImageOnlyDismisses() {
        var acceptedAttachments: [ChatAttachment] = []
        var dismissedViewControllers: [UIViewController] = []
        let workflow = makeWorkflow(
            acceptImportedAttachments: {
                acceptedAttachments.append(contentsOf: $0)
            },
            dismissViewController: {
                dismissedViewControllers.append($0)
            }
        )
        let picker = UIImagePickerController()

        workflow.imagePickerController(picker, didFinishPickingMediaWithInfo: [:])

        XCTAssertEqual(dismissedViewControllers, [picker])
        XCTAssertTrue(acceptedAttachments.isEmpty)
    }

    func testCameraCancelDismissesWithoutImporting() {
        var acceptedAttachments: [ChatAttachment] = []
        var dismissedViewControllers: [UIViewController] = []
        let workflow = makeWorkflow(
            acceptImportedAttachments: {
                acceptedAttachments.append(contentsOf: $0)
            },
            dismissViewController: {
                dismissedViewControllers.append($0)
            }
        )
        let picker = UIImagePickerController()

        workflow.imagePickerControllerDidCancel(picker)

        XCTAssertEqual(dismissedViewControllers, [picker])
        XCTAssertTrue(acceptedAttachments.isEmpty)
    }

    func testDocumentPickImportsSuccessfulURLsAndReportsPartialErrors() throws {
        let validURL = try writeTemporaryFile(filename: "notes.txt", data: Data([0x04]))
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: validURL)
        }
        var acceptedAttachments: [ChatAttachment] = []
        var presentedErrors: [String] = []
        let workflow = makeWorkflow(
            acceptImportedAttachments: {
                acceptedAttachments.append(contentsOf: $0)
            },
            presentError: {
                presentedErrors.append($0)
            }
        )

        workflow.documentPicker(
            UIDocumentPickerViewController(forOpeningContentTypes: [.item]),
            didPickDocumentsAt: [validURL, missingURL]
        )

        XCTAssertEqual(acceptedAttachments.map(\.filename), ["notes.txt"])
        XCTAssertEqual(try attachmentStore.loadData(for: acceptedAttachments[0]), Data([0x04]))
        XCTAssertEqual(presentedErrors.count, 1)
    }

    func testPhotoPickerEmptyResultsDismissesWithoutImport() {
        var acceptedAttachments: [ChatAttachment] = []
        var dismissedViewControllers: [UIViewController] = []
        let workflow = makeWorkflow(
            acceptImportedAttachments: {
                acceptedAttachments.append(contentsOf: $0)
            },
            dismissViewController: {
                dismissedViewControllers.append($0)
            }
        )
        let picker = PHPickerViewController(configuration: PHPickerConfiguration())

        workflow.picker(picker, didFinishPicking: [])

        XCTAssertEqual(dismissedViewControllers, [picker])
        XCTAssertTrue(acceptedAttachments.isEmpty)
    }

    func testPhotoImportCompletionAcceptsAttachmentsAndReportsAllErrors() async {
        let importController = ChatAttachmentImportController(
            attachmentImporter: makeImporter(jpegData: Data([0xCA, 0xFE]))
        )
        let photoLibraryController = FakePhotoLibraryImportController()
        var acceptedAttachments: [ChatAttachment] = []
        var presentedErrors: [String] = []
        let workflow = ChatAttachmentAcquisitionWorkflow(
            importController: importController,
            photoLibraryImportController: photoLibraryController,
            acceptImportedAttachments: {
                acceptedAttachments.append(contentsOf: $0)
            },
            presentError: {
                presentedErrors.append($0)
            },
            presentViewController: { _ in }
        )
        let attachment = ChatAttachment(
            kind: .image,
            filename: "photo.jpg",
            contentType: "image/jpeg",
            relativePath: "photo.jpg"
        )
        let firstError = NSError(domain: "ChatAttachmentAcquisitionWorkflowTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "First"
        ])
        let secondError = NSError(domain: "ChatAttachmentAcquisitionWorkflowTests", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Second"
        ])

        workflow.importPhotoLibraryItems([
            ChatPhotoLibraryImportItem(
                suggestedName: "Photo",
                canLoadImage: true,
                loadImage: { UIImage() }
            )
        ])
        photoLibraryController.complete(
            ChatAttachmentImportResult(
                attachments: [attachment],
                errors: [firstError, secondError]
            )
        )
        await Task.yield()

        XCTAssertEqual(acceptedAttachments, [attachment])
        XCTAssertEqual(presentedErrors, ["First\nSecond"])
    }

    func testCancelStopsPhotoLibraryImport() {
        let photoLibraryController = FakePhotoLibraryImportController()
        let workflow = ChatAttachmentAcquisitionWorkflow(
            importController: ChatAttachmentImportController(attachmentImporter: makeImporter()),
            photoLibraryImportController: photoLibraryController,
            acceptImportedAttachments: { _ in },
            presentError: { _ in },
            presentViewController: { _ in }
        )

        workflow.cancel()

        XCTAssertEqual(photoLibraryController.cancelCount, 1)
    }

    private func makeWorkflow(
        jpegData: Data? = Data([0xCA, 0xFE]),
        acceptImportedAttachments: @escaping ChatAttachmentAcquisitionWorkflow.ImportedAttachmentsHandler = { _ in },
        presentError: @escaping ChatAttachmentAcquisitionWorkflow.ErrorPresenter = { _ in },
        presentViewController: @escaping ChatAttachmentAcquisitionWorkflow.ViewControllerPresenter = { makeViewController in
            _ = makeViewController()
        },
        dismissViewController: @escaping ChatAttachmentAcquisitionWorkflow.ViewControllerDismisser = { _ in },
        isCameraAvailable: @escaping ChatAttachmentAcquisitionWorkflow.CameraAvailability = { true },
        makeCameraPicker: @escaping ChatAttachmentAcquisitionWorkflow.CameraPickerBuilder = { _ in UIViewController() },
        makePhotoPicker: @escaping ChatAttachmentAcquisitionWorkflow.PhotoPickerBuilder = { _, _ in UIViewController() },
        makeDocumentPicker: @escaping ChatAttachmentAcquisitionWorkflow.DocumentPickerBuilder = { _, _, _, _ in UIViewController() }
    ) -> ChatAttachmentAcquisitionWorkflow {
        ChatAttachmentAcquisitionWorkflow(
            importController: ChatAttachmentImportController(
                attachmentImporter: makeImporter(jpegData: jpegData)
            ),
            photoLibraryImportController: ChatPhotoLibraryImportController(
                attachmentImporter: makeImporter(jpegData: jpegData)
            ),
            acceptImportedAttachments: acceptImportedAttachments,
            presentError: presentError,
            presentViewController: presentViewController,
            dismissViewController: dismissViewController,
            isCameraAvailable: isCameraAvailable,
            makeCameraPicker: makeCameraPicker,
            makePhotoPicker: makePhotoPicker,
            makeDocumentPicker: makeDocumentPicker
        )
    }

    private func makeImporter(
        jpegData: Data? = Data([0xCA, 0xFE])
    ) -> ChatAttachmentImporter {
        ChatAttachmentImporter(
            attachmentStore: attachmentStore,
            filenames: ChatAttachmentImportFilenames(
                capturedPhotoFilename: { "captured-\($0).jpg" },
                photoLibraryImageFilename: { "library-\($0).jpg" }
            ),
            jpegData: { _, _ in jpegData }
        )
    }

    private func writeTemporaryFile(filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentAcquisitionWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url)
        return url
    }
}

@MainActor
private final class FakePhotoLibraryImportController: ChatPhotoLibraryImportControlling {
    private var completion: (@MainActor (ChatAttachmentImportResult) -> Void)?
    private(set) var importedItems: [[ChatPhotoLibraryImportItem]] = []
    private(set) var cancelCount = 0

    func importItems(
        _ items: [ChatPhotoLibraryImportItem],
        didComplete: @escaping @MainActor (ChatAttachmentImportResult) -> Void
    ) -> Bool {
        importedItems.append(items)
        completion = didComplete
        return !items.isEmpty
    }

    func cancel() {
        cancelCount += 1
        completion = nil
    }

    func complete(_ result: ChatAttachmentImportResult) {
        completion?(result)
    }
}
