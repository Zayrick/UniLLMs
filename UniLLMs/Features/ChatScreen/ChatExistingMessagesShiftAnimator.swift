//
//  ChatExistingMessagesShiftAnimator.swift
//  UniLLMs
//
//  Keeps visible chat messages visually anchored while new message views are inserted.
//

import UIKit

@MainActor
final class ChatExistingMessagesShiftAnimator {
    struct Snapshot {
        fileprivate struct Entry {
            weak var view: UIView?
            var frame: CGRect
        }

        fileprivate var entries: [Entry]

        var frames: [CGRect] {
            entries.map(\.frame)
        }

        var isEmpty: Bool {
            entries.isEmpty
        }

        static var empty: Snapshot {
            Snapshot(entries: [])
        }
    }

    private weak var hostView: UIView?
    private weak var referenceView: UIView?
    private weak var scrollView: UIScrollView?
    private weak var stackView: UIStackView?
    private let visibilityMargin: CGFloat
    private let animationDuration: TimeInterval
    private let dampingRatio: CGFloat

    init(
        hostView: UIView,
        referenceView: UIView,
        scrollView: UIScrollView,
        stackView: UIStackView,
        visibilityMargin: CGFloat,
        animationDuration: TimeInterval,
        dampingRatio: CGFloat
    ) {
        self.hostView = hostView
        self.referenceView = referenceView
        self.scrollView = scrollView
        self.stackView = stackView
        self.visibilityMargin = visibilityMargin
        self.animationDuration = animationDuration
        self.dampingRatio = dampingRatio
    }

    func captureSnapshot() -> Snapshot {
        guard let referenceView,
              let scrollView,
              let stackView else {
            return Snapshot(entries: [])
        }

        let visibleFrame = scrollView.convert(
            scrollView.bounds.insetBy(
                dx: 0.0,
                dy: -visibilityMargin
            ),
            to: referenceView
        )
        let entries = stackView.arrangedSubviews.compactMap { messageView -> Snapshot.Entry? in
            let frame = messageView.convert(messageView.bounds, to: referenceView)
            guard frame.intersects(visibleFrame) else {
                return nil
            }

            return Snapshot.Entry(view: messageView, frame: frame)
        }
        return Snapshot(entries: entries)
    }

    func animateChanges(from snapshot: Snapshot) {
        guard let hostView,
              let referenceView,
              hostView.window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            return
        }

        let shiftedViews = snapshot.entries.compactMap { entry -> UIView? in
            guard let view = entry.view,
                  view.superview != nil else {
                return nil
            }

            let currentFrame = view.convert(view.bounds, to: referenceView)
            let deltaY = entry.frame.minY - currentFrame.minY
            guard abs(deltaY) > 0.5 else {
                return nil
            }

            view.transform = CGAffineTransform(translationX: 0.0, y: deltaY)
            return view
        }

        guard !shiftedViews.isEmpty else {
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: animationDuration,
            dampingRatio: dampingRatio
        ) {
            shiftedViews.forEach { messageView in
                messageView.transform = .identity
            }
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.addCompletion { _ in
            shiftedViews.forEach { messageView in
                messageView.transform = .identity
            }
        }
        animator.startAnimation()
    }
}
