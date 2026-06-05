//
//  ChatIdleModalPresenterTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatIdleModalPresenterTests: XCTestCase {
    func testPresentIgnoresWhenModalIsAlreadyPresentedWithoutBuildingViewController() {
        var didEndEditing = false
        var didBuild = false
        var didPresent = false
        let presenter = ChatIdleModalPresenter(
            isPresentingModal: { true },
            endEditing: { didEndEditing = true },
            presentViewController: { _ in didPresent = true }
        )

        let didStartPresentation = presenter.presentIfIdle {
            didBuild = true
            return UIViewController()
        }

        XCTAssertFalse(didStartPresentation)
        XCTAssertFalse(didEndEditing)
        XCTAssertFalse(didBuild)
        XCTAssertFalse(didPresent)
    }

    func testPresentBuildsThenEndsEditingAndPresentsWhenIdle() {
        let viewController = UIViewController()
        var events: [Event] = []
        let presenter = ChatIdleModalPresenter(
            isPresentingModal: { false },
            endEditing: { events.append(.endEditing) },
            presentViewController: { presentedViewController in
                events.append(.present(presentedViewController))
            }
        )

        let didStartPresentation = presenter.presentIfIdle {
            events.append(.build)
            return viewController
        }

        XCTAssertTrue(didStartPresentation)
        XCTAssertEqual(events, [
            .build,
            .endEditing,
            .present(viewController)
        ])
    }

    func testPresentCanPreserveCurrentKeyboardState() {
        var events: [Event] = []
        let presenter = ChatIdleModalPresenter(
            isPresentingModal: { false },
            endEditing: { events.append(.endEditing) },
            presentViewController: { presentedViewController in
                events.append(.present(presentedViewController))
            }
        )

        let didStartPresentation = presenter.presentIfIdle(endEditing: false) {
            let viewController = UIViewController()
            events.append(.build)
            return viewController
        }

        XCTAssertTrue(didStartPresentation)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .build)
        if case .present = events.last {
            return
        }
        XCTFail("Expected the second event to present the built view controller.")
    }

    func testPresentIgnoresNilBuilderResultWithoutEndingEditingOrPresenting() {
        var didEndEditing = false
        var didPresent = false
        let presenter = ChatIdleModalPresenter(
            isPresentingModal: { false },
            endEditing: { didEndEditing = true },
            presentViewController: { _ in didPresent = true }
        )

        let didStartPresentation = presenter.presentIfIdle {
            nil
        }

        XCTAssertFalse(didStartPresentation)
        XCTAssertFalse(didEndEditing)
        XCTAssertFalse(didPresent)
    }

    private enum Event: Equatable {
        case endEditing
        case build
        case present(UIViewController)

        static func == (lhs: Event, rhs: Event) -> Bool {
            switch (lhs, rhs) {
            case (.endEditing, .endEditing),
                 (.build, .build):
                return true
            case let (.present(lhsViewController), .present(rhsViewController)):
                return lhsViewController === rhsViewController
            case (.endEditing, _),
                 (.build, _),
                 (.present, _):
                return false
            }
        }
    }
}
