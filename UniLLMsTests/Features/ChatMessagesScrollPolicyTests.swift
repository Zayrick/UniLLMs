//
//  ChatMessagesScrollPolicyTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatMessagesScrollPolicyTests: XCTestCase {
    func testBottomLockedContentGrowthFollowsWithAnimationWhenAllowed() {
        let previous = snapshot(contentHeight: 400, boundsHeight: 300, offsetY: 100)
        let current = snapshot(contentHeight: 500, boundsHeight: 300, offsetY: 100)

        let decision = ChatMessagesScrollPolicy.reconcileAfterLayout(
            isBottomLocked: true,
            previousSnapshot: previous,
            currentSnapshot: current,
            allowsAnimatedFollow: true,
            isUserInteracting: false
        )

        XCTAssertEqual(decision, .followToBottom(animated: true))
    }

    func testBottomLockedFollowDoesNotAnimateWithoutPreviousSnapshot() {
        let current = snapshot(contentHeight: 500, boundsHeight: 300, offsetY: 100)

        let decision = ChatMessagesScrollPolicy.reconcileAfterLayout(
            isBottomLocked: true,
            previousSnapshot: nil,
            currentSnapshot: current,
            allowsAnimatedFollow: true,
            isUserInteracting: false
        )

        XCTAssertEqual(decision, .followToBottom(animated: false))
    }

    func testBottomLockedViewportChangeDisablesFollowAnimation() {
        let previous = snapshot(contentHeight: 400, boundsHeight: 300, offsetY: 100)
        let current = snapshot(contentHeight: 500, boundsHeight: 280, offsetY: 100)

        let decision = ChatMessagesScrollPolicy.reconcileAfterLayout(
            isBottomLocked: true,
            previousSnapshot: previous,
            currentSnapshot: current,
            allowsAnimatedFollow: true,
            isUserInteracting: false
        )

        XCTAssertEqual(decision, .followToBottom(animated: false))
    }

    func testUnlockedLayoutClampsOffsetBelowMinimumWhenUserIsNotInteracting() {
        let current = snapshot(
            contentHeight: 200,
            boundsHeight: 300,
            topInset: 20,
            bottomInset: 10,
            offsetY: -30
        )

        let decision = ChatMessagesScrollPolicy.reconcileAfterLayout(
            isBottomLocked: false,
            previousSnapshot: nil,
            currentSnapshot: current,
            allowsAnimatedFollow: true,
            isUserInteracting: false
        )

        XCTAssertEqual(decision, .clamp(toOffsetY: -20))
    }

    func testUnlockedLayoutKeepsOffsetWhileUserIsInteracting() {
        let current = snapshot(
            contentHeight: 200,
            boundsHeight: 300,
            topInset: 20,
            bottomInset: 10,
            offsetY: -30
        )

        let decision = ChatMessagesScrollPolicy.reconcileAfterLayout(
            isBottomLocked: false,
            previousSnapshot: nil,
            currentSnapshot: current,
            allowsAnimatedFollow: true,
            isUserInteracting: true
        )

        XCTAssertEqual(decision, .keepOffset)
    }

    func testBottomDetectionUsesTolerance() {
        XCTAssertTrue(
            ChatMessagesScrollPolicy.isScrolledToBottom(
                offsetY: 98.1,
                bottomOffsetY: 100,
                bottomLockTolerance: 2
            )
        )
        XCTAssertFalse(
            ChatMessagesScrollPolicy.isScrolledToBottom(
                offsetY: 97.9,
                bottomOffsetY: 100,
                bottomLockTolerance: 2
            )
        )
    }

    private func snapshot(
        contentHeight: CGFloat,
        boundsHeight: CGFloat,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        offsetY: CGFloat
    ) -> ChatMessagesScrollLayoutSnapshot {
        ChatMessagesScrollLayoutSnapshot(
            contentSize: CGSize(width: 320, height: contentHeight),
            boundsSize: CGSize(width: 320, height: boundsHeight),
            adjustedInsets: .init(top: topInset, bottom: bottomInset),
            contentOffsetY: offsetY
        )
    }
}
