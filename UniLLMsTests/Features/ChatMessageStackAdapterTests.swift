//
//  ChatMessageStackAdapterTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatMessageStackAdapterTests: XCTestCase {
    func testAppendOutgoingMessageAddsBubbleAndResponseViews() {
        let environment = makeEnvironment()
        let messageID = UUID()

        let outgoingViews = environment.adapter.appendOutgoingMessage(
            messageID: messageID,
            text: "Hello",
            attachments: [],
            initialBubbleAlpha: 0.25
        )

        XCTAssertEqual(environment.stackView.arrangedSubviews.count, 2)
        XCTAssertTrue(environment.stackView.arrangedSubviews[0] === outgoingViews.bubbleView)
        XCTAssertTrue(environment.stackView.arrangedSubviews[1] === outgoingViews.responseView)
        XCTAssertEqual(outgoingViews.bubbleView.messageID, messageID)
        XCTAssertEqual(outgoingViews.bubbleView.alpha, 0.25)
        XCTAssertTrue(outgoingViews.responseView.isHidden)
        XCTAssertEqual(environment.probe.configuredMessageIDs, [messageID])
        XCTAssertEqual(environment.probe.configuredBubbleMessageIDs, [messageID])
    }

    func testAppendSentMessageUsesAttachmentDisplayBuilder() {
        let attachment = Self.attachment(filename: "photo.png")
        var displayedAttachments: [ChatAttachment] = []
        let environment = makeEnvironment { attachments in
            displayedAttachments = attachments
            return ChatAttachmentPreviewDisplay.placeholders(for: attachments)
        }

        _ = environment.adapter.appendStoredUserMessage(
            id: UUID(),
            text: "Photo",
            attachments: [attachment]
        )

        XCTAssertEqual(displayedAttachments, [attachment])
    }

    func testAppendStoredUserMessageConfiguresActionsWithExplicitMessageID() {
        let messageID = UUID()
        let environment = makeEnvironment()

        _ = environment.adapter.appendStoredUserMessage(
            id: messageID,
            text: "Stored",
            attachments: []
        )

        XCTAssertEqual(environment.probe.configuredMessageIDs, [messageID])
        XCTAssertEqual(environment.probe.configuredBubbleMessageIDs, [messageID])
    }

    func testUpdateAttachmentDisplaysForMessageIDUpdatesMatchingBubble() throws {
        let messageID = UUID()
        let attachment = Self.attachment(filename: "photo.png")
        let firstImage = UIImage()
        let secondImage = UIImage()
        let environment = makeEnvironment { attachments in
            attachments.map {
                ChatAttachmentPreviewDisplay(attachment: $0, thumbnailImage: firstImage)
            }
        }
        let bubbleView = environment.adapter.appendStoredUserMessage(
            id: messageID,
            text: "Photo",
            attachments: [attachment]
        )

        XCTAssertTrue(
            environment.adapter.updateAttachmentDisplays(
                forMessageID: messageID,
                displays: [
                    ChatAttachmentPreviewDisplay(attachment: attachment, thumbnailImage: secondImage)
                ]
            )
        )

        XCTAssertFalse(Self.imageViews(in: bubbleView).contains { $0.image === firstImage })
        XCTAssertTrue(Self.imageViews(in: bubbleView).contains { $0.image === secondImage })
    }

    func testUpdateAttachmentDisplaysForMissingMessageIDReturnsFalse() {
        let attachment = Self.attachment(filename: "photo.png")
        let environment = makeEnvironment()

        XCTAssertFalse(
            environment.adapter.updateAttachmentDisplays(
                forMessageID: UUID(),
                displays: [
                    ChatAttachmentPreviewDisplay(attachment: attachment, thumbnailImage: UIImage())
                ]
            )
        )
    }

    func testContainsAndArrangedSubviewIndexFindSentMessageBubble() {
        let environment = makeEnvironment()
        let firstID = UUID()
        let secondID = UUID()
        _ = environment.adapter.appendStoredUserMessage(id: firstID, text: "First", attachments: [])
        _ = environment.adapter.appendStoredUserMessage(id: secondID, text: "Second", attachments: [])

        XCTAssertTrue(environment.adapter.containsSentMessage(withID: secondID))
        XCTAssertEqual(environment.adapter.arrangedSubviewIndexOfSentMessage(withID: secondID), 1)
        XCTAssertFalse(environment.adapter.containsSentMessage(withID: UUID()))
    }

    func testArrangedSubviewIndexCountsAssistantResponsesBetweenSentMessages() {
        let environment = makeEnvironment()
        let firstID = UUID()
        let secondID = UUID()
        _ = environment.adapter.appendOutgoingMessage(
            messageID: firstID,
            text: "First",
            attachments: []
        )
        _ = environment.adapter.appendStoredUserMessage(
            id: secondID,
            text: "Second",
            attachments: []
        )

        XCTAssertEqual(environment.stackView.arrangedSubviews.count, 3)
        XCTAssertEqual(environment.adapter.arrangedSubviewIndexOfSentMessage(withID: secondID), 2)
    }

    func testRemoveMessagesStartingRemovesArrangedSubviewsAndHierarchy() {
        let environment = makeEnvironment()
        let first = environment.adapter.appendStoredUserMessage(id: UUID(), text: "First", attachments: [])
        let second = environment.adapter.appendStoredUserMessage(id: UUID(), text: "Second", attachments: [])
        let response = environment.adapter.appendAssistantResponseView()

        environment.adapter.removeMessagesStarting(at: 1)

        XCTAssertEqual(environment.stackView.arrangedSubviews.count, 1)
        XCTAssertTrue(environment.stackView.arrangedSubviews[0] === first)
        XCTAssertNil(second.superview)
        XCTAssertNil(response.superview)
    }

    func testRemoveAllReturnsWhetherStackHadContent() {
        let environment = makeEnvironment()
        XCTAssertFalse(environment.adapter.removeAll())

        let bubble = environment.adapter.appendStoredUserMessage(id: UUID(), text: "Hello", attachments: [])
        XCTAssertTrue(environment.adapter.removeAll())

        XCTAssertTrue(environment.stackView.arrangedSubviews.isEmpty)
        XCTAssertNil(bubble.superview)
    }

    func testAppendAssistantResponseViewAddsInitiallyVisibleResponseViewForStoredContent() {
        let environment = makeEnvironment()

        let responseView = environment.adapter.appendAssistantResponseView()

        XCTAssertEqual(environment.stackView.arrangedSubviews.count, 1)
        XCTAssertTrue(environment.stackView.arrangedSubviews[0] === responseView)
        XCTAssertFalse(responseView.isHidden)
    }

    private func makeEnvironment(
        attachmentDisplayBuilder: @escaping ChatMessageStackAdapter.AttachmentDisplayBuilder = {
            ChatAttachmentPreviewDisplay.placeholders(for: $0)
        }
    ) -> (
        stackView: UIStackView,
        adapter: ChatMessageStackAdapter,
        probe: ConfigurationProbe
    ) {
        let stackView = UIStackView()
        let probe = ConfigurationProbe()
        let adapter = ChatMessageStackAdapter(
            stackView: stackView,
            maximumBubbleWidthRatio: 0.8,
            attachmentDisplayBuilder: attachmentDisplayBuilder
        ) { bubbleView, messageID in
            probe.configuredMessageIDs.append(messageID)
            probe.configuredBubbleMessageIDs.append(bubbleView.messageID)
        }
        return (stackView, adapter, probe)
    }

    private static func attachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            kind: .image,
            filename: filename,
            contentType: "image/png",
            relativePath: filename
        )
    }

    private static func imageViews(in view: UIView) -> [UIImageView] {
        allSubviews(in: view).compactMap { $0 as? UIImageView }
    }

    private static func allSubviews(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    private final class ConfigurationProbe {
        var configuredMessageIDs: [UUID] = []
        var configuredBubbleMessageIDs: [UUID] = []
    }
}
