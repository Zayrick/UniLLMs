//
//  ChatPageSheetPresentationTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatPageSheetPresentationTests: XCTestCase {
    func testApplyUsesPageSheetPresentationStyle() throws {
        let viewController = UIViewController()

        ChatPageSheetPresentation.apply(to: viewController)

        XCTAssertEqual(viewController.modalPresentationStyle, .pageSheet)
    }

    func testApplyCanConfigureMediumAndLargeDetentsWithGrabber() throws {
        let viewController = UIViewController()

        ChatPageSheetPresentation.apply(
            to: viewController,
            detentStyle: .mediumAndLarge,
            showsGrabber: true
        )

        let sheet = try XCTUnwrap(viewController.sheetPresentationController)
        XCTAssertEqual(sheet.detents.count, 2)
        XCTAssertTrue(sheet.prefersGrabberVisible)
    }

    func testWrapInNavigationControllerAppliesPageSheetPolicyToNavigationContainer() throws {
        let rootViewController = UIViewController()

        let navigationController = ChatPageSheetPresentation.wrapInNavigationController(
            rootViewController: rootViewController,
            detentStyle: .mediumAndLarge,
            showsGrabber: true
        )

        XCTAssertEqual(navigationController.viewControllers.count, 1)
        XCTAssertTrue(navigationController.viewControllers.first === rootViewController)
        XCTAssertEqual(navigationController.modalPresentationStyle, .pageSheet)
        let sheet = try XCTUnwrap(navigationController.sheetPresentationController)
        XCTAssertEqual(sheet.detents.count, 2)
        XCTAssertTrue(sheet.prefersGrabberVisible)
    }
}
