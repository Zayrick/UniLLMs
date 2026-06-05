//
//  ChatComposerAddWorkflowTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatComposerAddWorkflowTests: XCTestCase {
    func testMakeAddSheetAppliesDefaultPresentationAndRoutesActions() throws {
        var routedActions: [String] = []
        let workflow = makeWorkflow(
            presentFiles: {
                routedActions.append("files")
            }
        )

        let viewController = workflow.makeAddSheetViewController()
        let addSheet = try XCTUnwrap(viewController as? ComposerAddSheetViewController)
        addSheet.onAction?(.files)

        let sheet = try XCTUnwrap(addSheet.sheetPresentationController)
        XCTAssertEqual(addSheet.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(sheet.detents.count, 2)
        XCTAssertTrue(sheet.prefersGrabberVisible)
        XCTAssertNotNil(addSheet.preferredTransition)
        XCTAssertEqual(routedActions, ["files"])
    }

    func testRouteDispatchesAllActions() {
        var routedActions: [String] = []
        let workflow = makeWorkflow(
            presentSystemPrompt: {
                routedActions.append("systemPrompt")
            },
            presentCamera: {
                routedActions.append("camera")
            },
            presentPhotoLibrary: {
                routedActions.append("photoLibrary")
            },
            presentFiles: {
                routedActions.append("files")
            }
        )

        workflow.route(.systemPrompt)
        workflow.route(.camera)
        workflow.route(.photoLibrary)
        workflow.route(.files)

        XCTAssertEqual(routedActions, [
            "systemPrompt",
            "camera",
            "photoLibrary",
            "files"
        ])
    }

    func testMakeAddSheetUsesInjectedBuilderAndPresentation() throws {
        let expectedSheet = ComposerAddSheetViewController()
        var presentedViewController: UIViewController?
        let workflow = makeWorkflow(
            makeAddSheet: {
                expectedSheet
            },
            applyPresentation: { viewController in
                presentedViewController = viewController
                viewController.modalPresentationStyle = .formSheet
            }
        )

        let viewController = workflow.makeAddSheetViewController()

        XCTAssertTrue(viewController === expectedSheet)
        XCTAssertTrue(presentedViewController === expectedSheet)
        XCTAssertEqual(expectedSheet.modalPresentationStyle, .formSheet)
        XCTAssertNotNil(expectedSheet.onAction)
    }

    private func makeWorkflow(
        presentSystemPrompt: @escaping () -> Void = {},
        presentCamera: @escaping () -> Void = {},
        presentPhotoLibrary: @escaping () -> Void = {},
        presentFiles: @escaping () -> Void = {},
        makeAddSheet: @escaping ChatComposerAddWorkflow.AddSheetBuilder = { ComposerAddSheetViewController() },
        applyPresentation: @escaping ChatComposerAddWorkflow.PresentationApplier = { viewController in
            ChatPageSheetPresentation.apply(
                to: viewController,
                detentStyle: .mediumAndLarge,
                showsGrabber: true
            )
        }
    ) -> ChatComposerAddWorkflow {
        ChatComposerAddWorkflow(
            sourceView: { nil },
            presentSystemPromptSelection: presentSystemPrompt,
            presentCameraPicker: presentCamera,
            presentPhotoLibraryPicker: presentPhotoLibrary,
            presentDocumentPicker: presentFiles,
            makeAddSheet: makeAddSheet,
            applyPresentation: applyPresentation
        )
    }
}
