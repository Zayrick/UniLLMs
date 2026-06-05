//
//  ChatMessagesScrollCoordinator.swift
//  UniLLMs
//
//  Adapts chat message scroll layout policy decisions to a UIScrollView.
//

import UIKit

final class MessagesScrollCoordinator {
    private weak var scrollView: UIScrollView?
    private let bottomLockTolerance: CGFloat
    private let autoScrollAnimationDuration: TimeInterval

    private var isBottomLocked = true
    private var lastLayoutSnapshot: ChatMessagesScrollLayoutSnapshot?
    private var animationGeneration = 0

    init(
        scrollView: UIScrollView,
        bottomLockTolerance: CGFloat,
        autoScrollAnimationDuration: TimeInterval
    ) {
        self.scrollView = scrollView
        self.bottomLockTolerance = bottomLockTolerance
        self.autoScrollAnimationDuration = autoScrollAnimationDuration
    }

    func lockToBottom() {
        isBottomLocked = true
    }

    func scrollToBottom(hostView: UIView?, animated: Bool) {
        guard let scrollView else {
            return
        }

        isBottomLocked = true
        setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: bottomOffsetY()),
            hostView: hostView,
            animated: animated
        )
        recordCurrentLayout()
    }

    func reconcileAfterLayout(hostView: UIView?, allowsAnimatedFollow: Bool) {
        guard let scrollView else {
            return
        }

        let snapshot = currentLayoutSnapshot()
        let decision = ChatMessagesScrollPolicy.reconcileAfterLayout(
            isBottomLocked: isBottomLocked,
            previousSnapshot: lastLayoutSnapshot,
            currentSnapshot: snapshot,
            allowsAnimatedFollow: allowsAnimatedFollow,
            isUserInteracting: isUserInteracting
        )

        switch decision {
        case let .followToBottom(animated):
            setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: snapshot.bottomOffsetY),
                hostView: hostView,
                animated: animated
            )
        case let .clamp(offsetY):
            setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: offsetY),
                hostView: hostView,
                animated: false
            )
        case .keepOffset:
            break
        }

        recordCurrentLayout()
    }

    func userWillBeginDragging() {
        isBottomLocked = false
        cancelInFlightScrollAnimation()
    }

    func userDidScroll() {
        isBottomLocked = isScrolledToBottom()
    }

    func userWillEndDragging(targetOffsetY: CGFloat) {
        isBottomLocked = isScrolledToBottom(offsetY: targetOffsetY)
    }

    func userDidFinishScrolling() {
        isBottomLocked = isScrolledToBottom()
    }

    private func setContentOffset(
        _ contentOffset: CGPoint,
        hostView: UIView?,
        animated: Bool
    ) {
        guard let scrollView else {
            return
        }

        guard animated,
              hostView?.window != nil,
              !UIAccessibility.isReduceMotionEnabled,
              abs(scrollView.contentOffset.y - contentOffset.y) > ChatMessagesScrollPolicy.layoutEpsilon else {
            animationGeneration += 1
            scrollView.setContentOffset(contentOffset, animated: false)
            return
        }

        animationGeneration += 1
        let generation = animationGeneration
        UIView.animate(
            withDuration: autoScrollAnimationDuration,
            delay: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            scrollView.contentOffset = contentOffset
        } completion: { [weak self, weak scrollView] _ in
            guard let self,
                  let scrollView,
                  generation == self.animationGeneration,
                  self.isBottomLocked,
                  !self.isUserInteracting else {
                return
            }

            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: self.bottomOffsetY()),
                animated: false
            )
            self.recordCurrentLayout()
        }
    }

    private func cancelInFlightScrollAnimation() {
        animationGeneration += 1
        scrollView?.layer.removeAnimation(forKey: "bounds")
    }

    private var isUserInteracting: Bool {
        guard let scrollView else {
            return false
        }

        return scrollView.isTracking
            || scrollView.isDragging
            || scrollView.isDecelerating
    }

    private func isScrolledToBottom(offsetY: CGFloat? = nil) -> Bool {
        guard let scrollView else {
            return true
        }

        let candidateOffsetY = offsetY ?? scrollView.contentOffset.y
        return ChatMessagesScrollPolicy.isScrolledToBottom(
            offsetY: candidateOffsetY,
            bottomOffsetY: bottomOffsetY(),
            bottomLockTolerance: bottomLockTolerance
        )
    }

    private func bottomOffsetY() -> CGFloat {
        currentLayoutSnapshot().bottomOffsetY
    }

    private func currentLayoutSnapshot() -> ChatMessagesScrollLayoutSnapshot {
        guard let scrollView else {
            return ChatMessagesScrollLayoutSnapshot(
                contentSize: .zero,
                boundsSize: .zero,
                adjustedInsets: .init(top: 0.0, bottom: 0.0),
                contentOffsetY: 0.0
            )
        }

        let adjustedInsets = scrollView.adjustedContentInset
        return ChatMessagesScrollLayoutSnapshot(
            contentSize: scrollView.contentSize,
            boundsSize: scrollView.bounds.size,
            adjustedInsets: .init(
                top: adjustedInsets.top,
                bottom: adjustedInsets.bottom
            ),
            contentOffsetY: scrollView.contentOffset.y
        )
    }

    private func recordCurrentLayout() {
        lastLayoutSnapshot = currentLayoutSnapshot()
    }
}
