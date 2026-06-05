//
//  ChatMessageActionPresentationTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatMessageActionPresentationTests: XCTestCase {
    func testEditorPresentationWrapsEditorInStandardPageSheet() throws {
        let presentationController = ChatMessageActionPresentation.makeEditor(
            text: "Hello",
            attachments: [],
            onSubmit: { _ in }
        )

        let navigationController = try XCTUnwrap(presentationController as? UINavigationController)
        let editorViewController = try XCTUnwrap(navigationController.viewControllers.first as? MessageEditViewController)
        let sheet = try XCTUnwrap(navigationController.sheetPresentationController)
        XCTAssertEqual(navigationController.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(sheet.detents.count, 2)
        XCTAssertTrue(sheet.prefersGrabberVisible)
        XCTAssertNotNil(editorViewController.onSubmit)
    }

    func testRevisionHistoryPresentationWrapsHistoryInStandardPageSheet() throws {
        let presentationController = ChatMessageActionPresentation.makeRevisionHistory(
            revisions: [],
            onSelectRevision: { _ in }
        )

        let navigationController = try XCTUnwrap(presentationController as? UINavigationController)
        let historyViewController = try XCTUnwrap(navigationController.viewControllers.first as? MessageRevisionHistoryViewController)
        let sheet = try XCTUnwrap(navigationController.sheetPresentationController)
        XCTAssertEqual(navigationController.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(sheet.detents.count, 2)
        XCTAssertTrue(sheet.prefersGrabberVisible)
        XCTAssertNotNil(historyViewController.onSelectRevision)
    }
}
