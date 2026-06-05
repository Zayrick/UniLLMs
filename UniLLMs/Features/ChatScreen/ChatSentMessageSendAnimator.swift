//
//  ChatSentMessageSendAnimator.swift
//  UniLLMs
//
//  Animates a sent message bubble from the composer into the chat message stack.
//

import UIKit

@MainActor
protocol ChatSentMessageSendAnimating: AnyObject {
    func animate(
        bubbleView: SentMessageBubbleView,
        transition: ChatComposerSendTransition,
        attachments: [ChatAttachment],
        completion: (() -> Void)?
    )
}

@MainActor
final class ChatSentMessageSendAnimator: ChatSentMessageSendAnimating {
    typealias AttachmentDisplayBuilder = @MainActor ([ChatAttachment]) -> [ChatAttachmentPreviewDisplay]

    private weak var hostView: UIView?
    private weak var referenceView: UIView?
    private let animationDuration: TimeInterval
    private let dampingRatio: CGFloat
    private let isReduceMotionEnabled: @MainActor () -> Bool
    private let attachmentDisplayBuilder: AttachmentDisplayBuilder

    init(
        hostView: UIView,
        referenceView: UIView,
        animationDuration: TimeInterval,
        dampingRatio: CGFloat,
        isReduceMotionEnabled: @escaping @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled },
        attachmentDisplayBuilder: @escaping AttachmentDisplayBuilder = {
            ChatAttachmentPreviewDisplay.placeholders(for: $0)
        }
    ) {
        self.hostView = hostView
        self.referenceView = referenceView
        self.animationDuration = animationDuration
        self.dampingRatio = dampingRatio
        self.isReduceMotionEnabled = isReduceMotionEnabled
        self.attachmentDisplayBuilder = attachmentDisplayBuilder
    }

    func animate(
        bubbleView: SentMessageBubbleView,
        transition: ChatComposerSendTransition,
        attachments: [ChatAttachment] = [],
        completion: (() -> Void)? = nil
    ) {
        guard let hostView,
              let referenceView,
              hostView.window != nil,
              !isReduceMotionEnabled() else {
            bubbleView.alpha = 1.0
            completion?()
            return
        }

        let sourceBackgroundFrame = referenceView.convert(
            transition.backgroundGlobalFrame,
            from: nil
        )
        let targetBubbleFrame = bubbleView.convert(
            bubbleView.bounds,
            to: referenceView
        )

        let animatedBubbleView = SentMessageBubbleView(
            text: transition.text,
            attachments: attachments,
            attachmentDisplays: attachmentDisplayBuilder(attachments)
        )
        animatedBubbleView.frame = sourceBackgroundFrame
        animatedBubbleView.alpha = 0.0
        animatedBubbleView.isUserInteractionEnabled = false
        animatedBubbleView.layoutIfNeeded()
        referenceView.addSubview(animatedBubbleView)

        let animator = UIViewPropertyAnimator(
            duration: animationDuration,
            dampingRatio: dampingRatio
        ) {
            animatedBubbleView.frame = targetBubbleFrame
            animatedBubbleView.alpha = 1.0
            animatedBubbleView.layoutIfNeeded()
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.addCompletion { _ in
            UIView.performWithoutAnimation {
                animatedBubbleView.removeFromSuperview()
                bubbleView.alpha = 1.0
            }
            completion?()
        }
        animator.startAnimation()
    }
}
