//
//  ChatAttachmentPreviewWorkflowTests.swift
//  UniLLMsTests
//

import QuickLook
import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatAttachmentPreviewWorkflowTests: XCTestCase {
    func testPresentPreviewReturnsWhenAnotherModalIsPresented() {
        var didResolveFileURL = false
        var didPresent = false
        let workflow = makeWorkflow(
            previewController: ChatAttachmentPreviewController(
                fileURL: { _ in
                    didResolveFileURL = true
                    return URL(fileURLWithPath: "/tmp/report.pdf")
                },
                canPreview: { _ in true }
            ),
            isPresentingModal: { true },
            presentViewController: { _ in didPresent = true }
        )

        workflow.presentPreview(for: Self.attachment(filename: "Report"))

        XCTAssertFalse(didResolveFileURL)
        XCTAssertFalse(didPresent)
    }

    func testPresentPreviewReportsMissingFileWithoutPresentingQuickLook() {
        var didEndEditing = false
        var didPresent = false
        var presentedErrors: [String] = []
        let workflow = makeWorkflow(
            previewController: ChatAttachmentPreviewController(
                fileURL: { _ in nil },
                canPreview: { _ in true }
            ),
            endEditing: { didEndEditing = true },
            presentViewController: { _ in didPresent = true },
            presentError: { presentedErrors.append($0) }
        )

        workflow.presentPreview(for: Self.attachment(filename: "Missing"))

        XCTAssertFalse(didEndEditing)
        XCTAssertFalse(didPresent)
        XCTAssertEqual(presentedErrors, [String(localized: .chatAttachmentFileMissing)])
    }

    func testPresentPreviewReportsUnsupportedFileWithoutPresentingQuickLook() {
        var didEndEditing = false
        var didPresent = false
        var presentedErrors: [String] = []
        let workflow = makeWorkflow(
            previewController: ChatAttachmentPreviewController(
                fileURL: { _ in URL(fileURLWithPath: "/tmp/unsupported.bin") },
                canPreview: { _ in false }
            ),
            endEditing: { didEndEditing = true },
            presentViewController: { _ in didPresent = true },
            presentError: { presentedErrors.append($0) }
        )

        workflow.presentPreview(for: Self.attachment(filename: "Unsupported"))

        XCTAssertFalse(didEndEditing)
        XCTAssertFalse(didPresent)
        XCTAssertEqual(presentedErrors, [String(localized: .chatAttachmentPreviewUnavailable)])
    }

    func testPresentPreviewConfiguresQuickLookControllerAndPresentsIt() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let quickLookController = QLPreviewController()
        var didEndEditing = false
        var presentedViewController: UIViewController?
        let workflow = makeWorkflow(
            previewController: ChatAttachmentPreviewController(
                fileURL: { _ in fileURL },
                canPreview: { _ in true }
            ),
            endEditing: { didEndEditing = true },
            presentViewController: { presentedViewController = $0 },
            makePreviewController: { quickLookController }
        )

        workflow.presentPreview(for: Self.attachment(filename: "Report"))

        XCTAssertTrue(didEndEditing)
        XCTAssertTrue(presentedViewController === quickLookController)
        XCTAssertEqual(quickLookController.currentPreviewItemIndex, 0)
        XCTAssertTrue((quickLookController.dataSource as AnyObject?) === workflow)
        XCTAssertTrue((quickLookController.delegate as AnyObject?) === workflow)
    }

    func testDataSourceUsesPreparedItemAndDismissClearsPreview() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let quickLookController = QLPreviewController()
        var presentedViewController: UIViewController?
        let workflow = makeWorkflow(
            previewController: ChatAttachmentPreviewController(
                fileURL: { _ in fileURL },
                canPreview: { _ in true }
            ),
            presentViewController: { presentedViewController = $0 },
            makePreviewController: { quickLookController }
        )

        workflow.presentPreview(for: Self.attachment(filename: "Report"))

        XCTAssertTrue(presentedViewController === quickLookController)
        XCTAssertEqual(workflow.numberOfPreviewItems(in: quickLookController), 1)

        let previewItem = workflow.previewController(quickLookController, previewItemAt: 0)
        XCTAssertEqual(previewItem.previewItemURL, fileURL)
        XCTAssertEqual(previewItem.previewItemTitle, "Report")

        workflow.previewControllerDidDismiss(quickLookController)

        XCTAssertEqual(workflow.numberOfPreviewItems(in: quickLookController), 0)
    }

    private func makeWorkflow(
        previewController: ChatAttachmentPreviewController,
        isPresentingModal: @escaping ChatAttachmentPreviewWorkflow.ModalPresentationState = { false },
        endEditing: @escaping ChatAttachmentPreviewWorkflow.EndEditing = {},
        presentViewController: @escaping ChatAttachmentPreviewWorkflow.ViewControllerPresenter = { _ in },
        presentError: @escaping ChatAttachmentPreviewWorkflow.ErrorPresenter = { _ in },
        makePreviewController: @escaping ChatAttachmentPreviewWorkflow.PreviewControllerBuilder = { QLPreviewController() }
    ) -> ChatAttachmentPreviewWorkflow {
        ChatAttachmentPreviewWorkflow(
            previewController: previewController,
            isPresentingModal: isPresentingModal,
            endEditing: endEditing,
            presentViewController: presentViewController,
            presentError: presentError,
            makePreviewController: makePreviewController
        )
    }

    private static func attachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            kind: .file,
            filename: filename,
            contentType: "application/pdf",
            relativePath: filename
        )
    }
}
