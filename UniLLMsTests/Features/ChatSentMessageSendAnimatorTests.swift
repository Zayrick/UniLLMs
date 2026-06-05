//
//  ChatSentMessageSendAnimatorTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatSentMessageSendAnimatorTests: XCTestCase {
    func testAnimateCompletesImmediatelyWhenHostIsOffscreen() {
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 240.0))
        let bubbleView = SentMessageBubbleView(text: "Hello")
        bubbleView.alpha = 0.0
        hostView.addSubview(bubbleView)
        let animator = ChatSentMessageSendAnimator(
            hostView: hostView,
            referenceView: hostView,
            animationDuration: 0.2,
            dampingRatio: 1.0
        )
        var didComplete = false

        animator.animate(
            bubbleView: bubbleView,
            transition: ChatComposerSendTransition(
                text: "Hello",
                backgroundGlobalFrame: .zero
            )
        ) {
            didComplete = true
        }

        XCTAssertEqual(bubbleView.alpha, 1.0)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(hostView.subviews.count, 1)
        XCTAssertTrue(hostView.subviews.first === bubbleView)
    }

    func testAnimateCompletesImmediatelyWhenReduceMotionIsEnabled() throws {
        let window = try Self.makeWindow()
        let hostView = UIView(frame: window.bounds)
        let bubbleView = SentMessageBubbleView(text: "Hello")
        bubbleView.alpha = 0.0
        window.addSubview(hostView)
        hostView.addSubview(bubbleView)
        let animator = ChatSentMessageSendAnimator(
            hostView: hostView,
            referenceView: hostView,
            animationDuration: 0.2,
            dampingRatio: 1.0,
            isReduceMotionEnabled: { true }
        )
        var didComplete = false

        animator.animate(
            bubbleView: bubbleView,
            transition: ChatComposerSendTransition(
                text: "Hello",
                backgroundGlobalFrame: .zero
            )
        ) {
            didComplete = true
        }

        XCTAssertEqual(bubbleView.alpha, 1.0)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(hostView.subviews.count, 1)
        XCTAssertTrue(hostView.subviews.first === bubbleView)
    }

    func testAnimateUsesAttachmentDisplayBuilderForAnimatedBubble() throws {
        let window = try Self.makeWindow()
        let hostView = UIView(frame: window.bounds)
        let referenceView = UIView(frame: window.bounds)
        let bubbleView = SentMessageBubbleView(text: "Hello")
        let attachment = ChatAttachment(
            kind: .image,
            filename: "photo.png",
            contentType: "image/png",
            relativePath: "photo.png"
        )
        var displayedAttachments: [ChatAttachment] = []
        window.addSubview(hostView)
        hostView.addSubview(referenceView)
        referenceView.addSubview(bubbleView)
        bubbleView.frame = CGRect(x: 20.0, y: 20.0, width: 160.0, height: 80.0)
        let animator = ChatSentMessageSendAnimator(
            hostView: hostView,
            referenceView: referenceView,
            animationDuration: 0.2,
            dampingRatio: 1.0,
            isReduceMotionEnabled: { false },
            attachmentDisplayBuilder: { attachments in
                displayedAttachments = attachments
                return ChatAttachmentPreviewDisplay.placeholders(for: attachments)
            }
        )

        animator.animate(
            bubbleView: bubbleView,
            transition: ChatComposerSendTransition(
                text: "Hello",
                backgroundGlobalFrame: CGRect(x: 10.0, y: 10.0, width: 160.0, height: 80.0)
            ),
            attachments: [attachment]
        )

        XCTAssertEqual(displayedAttachments, [attachment])
    }

    private static func makeWindow() throws -> UIWindow {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("A UIWindowScene is required for this animation test.")
        }

        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0.0, y: 0.0, width: 320.0, height: 240.0)
        return window
    }
}
