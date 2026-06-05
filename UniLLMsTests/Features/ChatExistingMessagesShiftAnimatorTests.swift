//
//  ChatExistingMessagesShiftAnimatorTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatExistingMessagesShiftAnimatorTests: XCTestCase {
    func testCaptureSnapshotIncludesOnlyVisibleArrangedSubviewsWithinMargin() {
        let environment = makeEnvironment(visibilityMargin: 20.0)
        let visibleView = arrangedView(frame: CGRect(x: 0.0, y: 10.0, width: 100.0, height: 20.0))
        let marginView = arrangedView(frame: CGRect(x: 0.0, y: 108.0, width: 100.0, height: 10.0))
        let offscreenView = arrangedView(frame: CGRect(x: 0.0, y: 140.0, width: 100.0, height: 10.0))
        for view in [visibleView, marginView, offscreenView] {
            environment.stackView.addArrangedSubview(view)
        }

        let snapshot = environment.animator.captureSnapshot()

        XCTAssertEqual(snapshot.frames.count, 2)
        XCTAssertEqual(snapshot.frames.map(\.minY), [10.0, 108.0])
    }

    func testAnimateChangesDoesNothingWhenHostViewIsOffscreen() {
        let environment = makeEnvironment(visibilityMargin: 20.0)
        let visibleView = arrangedView(frame: CGRect(x: 0.0, y: 10.0, width: 100.0, height: 20.0))
        environment.stackView.addArrangedSubview(visibleView)
        let snapshot = environment.animator.captureSnapshot()

        visibleView.frame.origin.y = 50.0
        environment.animator.animateChanges(from: snapshot)

        XCTAssertEqual(visibleView.transform, .identity)
    }

    private func makeEnvironment(
        visibilityMargin: CGFloat
    ) -> (
        stackView: UIStackView,
        animator: ChatExistingMessagesShiftAnimator
    ) {
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 240.0))
        let scrollView = UIScrollView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 100.0))
        let stackView = UIStackView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 200.0))
        hostView.addSubview(scrollView)
        scrollView.addSubview(stackView)
        let animator = ChatExistingMessagesShiftAnimator(
            hostView: hostView,
            referenceView: hostView,
            scrollView: scrollView,
            stackView: stackView,
            visibilityMargin: visibilityMargin,
            animationDuration: 0.2,
            dampingRatio: 1.0
        )
        return (stackView, animator)
    }

    private func arrangedView(frame: CGRect) -> UIView {
        let view = UIView(frame: frame)
        view.bounds = CGRect(origin: .zero, size: frame.size)
        return view
    }
}
