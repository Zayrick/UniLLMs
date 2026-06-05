//
//  ChatMessagesScrollPolicy.swift
//  UniLLMs
//
//  Decides how the chat message list should follow layout changes.
//

import CoreGraphics
import Foundation

struct ChatMessagesScrollLayoutSnapshot: Equatable {
    struct VerticalInsets: Equatable {
        var top: CGFloat
        var bottom: CGFloat
    }

    var contentSize: CGSize
    var boundsSize: CGSize
    var adjustedInsets: VerticalInsets
    var contentOffsetY: CGFloat

    var bottomOffsetY: CGFloat {
        contentOffsetBounds.maximum
    }

    var contentOffsetBounds: (minimum: CGFloat, maximum: CGFloat) {
        let minimumOffsetY = -adjustedInsets.top
        let maximumOffsetY = max(
            minimumOffsetY,
            contentSize.height - boundsSize.height + adjustedInsets.bottom
        )
        return (minimumOffsetY, maximumOffsetY)
    }
}

struct ChatMessagesScrollPolicy: Equatable {
    enum ReconcileDecision: Equatable {
        case followToBottom(animated: Bool)
        case clamp(toOffsetY: CGFloat)
        case keepOffset
    }

    static let layoutEpsilon: CGFloat = 0.5

    static func reconcileAfterLayout(
        isBottomLocked: Bool,
        previousSnapshot: ChatMessagesScrollLayoutSnapshot?,
        currentSnapshot: ChatMessagesScrollLayoutSnapshot,
        allowsAnimatedFollow: Bool,
        isUserInteracting: Bool
    ) -> ReconcileDecision {
        if isBottomLocked {
            return .followToBottom(
                animated: shouldAnimateFollow(
                    previousSnapshot: previousSnapshot,
                    currentSnapshot: currentSnapshot,
                    allowsAnimatedFollow: allowsAnimatedFollow,
                    isUserInteracting: isUserInteracting
                )
            )
        }

        return clampedOffsetDecision(
            currentSnapshot: currentSnapshot,
            isUserInteracting: isUserInteracting
        )
    }

    static func isScrolledToBottom(
        offsetY: CGFloat,
        bottomOffsetY: CGFloat,
        bottomLockTolerance: CGFloat
    ) -> Bool {
        offsetY >= bottomOffsetY - bottomLockTolerance
    }

    private static func shouldAnimateFollow(
        previousSnapshot: ChatMessagesScrollLayoutSnapshot?,
        currentSnapshot: ChatMessagesScrollLayoutSnapshot,
        allowsAnimatedFollow: Bool,
        isUserInteracting: Bool
    ) -> Bool {
        guard allowsAnimatedFollow,
              !isUserInteracting,
              let previousSnapshot else {
            return false
        }

        return currentSnapshot.contentSize.height - previousSnapshot.contentSize.height > layoutEpsilon
            && currentSnapshot.bottomOffsetY - previousSnapshot.bottomOffsetY > layoutEpsilon
            && !viewportChanged(from: previousSnapshot, to: currentSnapshot)
    }

    private static func viewportChanged(
        from previousSnapshot: ChatMessagesScrollLayoutSnapshot,
        to currentSnapshot: ChatMessagesScrollLayoutSnapshot
    ) -> Bool {
        abs(currentSnapshot.boundsSize.height - previousSnapshot.boundsSize.height) > layoutEpsilon
            || abs(currentSnapshot.adjustedInsets.top - previousSnapshot.adjustedInsets.top) > layoutEpsilon
            || abs(currentSnapshot.adjustedInsets.bottom - previousSnapshot.adjustedInsets.bottom) > layoutEpsilon
    }

    private static func clampedOffsetDecision(
        currentSnapshot: ChatMessagesScrollLayoutSnapshot,
        isUserInteracting: Bool
    ) -> ReconcileDecision {
        guard !isUserInteracting else {
            return .keepOffset
        }

        let bounds = currentSnapshot.contentOffsetBounds
        let clampedOffsetY = min(
            max(currentSnapshot.contentOffsetY, bounds.minimum),
            bounds.maximum
        )
        guard abs(currentSnapshot.contentOffsetY - clampedOffsetY) > CGFloat.ulpOfOne else {
            return .keepOffset
        }

        return .clamp(toOffsetY: clampedOffsetY)
    }
}
