//
//  SentMessageBubbleViewTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class SentMessageBubbleViewTests: XCTestCase {
    func testUpdateAttachmentDisplaysUpdatesExistingImageForSameAttachmentID() {
        let attachment = Self.attachment(id: UUID(), filename: "photo.png")
        let firstImage = UIImage()
        let secondImage = UIImage()
        let bubbleView = SentMessageBubbleView(
            text: "Photo",
            attachments: [attachment],
            attachmentDisplays: [
                ChatAttachmentPreviewDisplay(attachment: attachment, thumbnailImage: firstImage)
            ]
        )

        bubbleView.updateAttachmentDisplays([
            ChatAttachmentPreviewDisplay(attachment: attachment, thumbnailImage: secondImage)
        ])

        XCTAssertFalse(Self.imageViews(in: bubbleView).contains { $0.image === firstImage })
        XCTAssertTrue(Self.imageViews(in: bubbleView).contains { $0.image === secondImage })
    }

    func testUpdateAttachmentDisplaysIgnoresDifferentAttachmentSequence() {
        let originalAttachment = Self.attachment(id: UUID(), filename: "original.png")
        let replacementAttachment = Self.attachment(id: UUID(), filename: "replacement.png")
        let originalImage = UIImage()
        let replacementImage = UIImage()
        let bubbleView = SentMessageBubbleView(
            text: "Photo",
            attachments: [originalAttachment],
            attachmentDisplays: [
                ChatAttachmentPreviewDisplay(attachment: originalAttachment, thumbnailImage: originalImage)
            ]
        )

        bubbleView.updateAttachmentDisplays([
            ChatAttachmentPreviewDisplay(attachment: replacementAttachment, thumbnailImage: replacementImage)
        ])

        XCTAssertTrue(Self.imageViews(in: bubbleView).contains { $0.image === originalImage })
        XCTAssertFalse(Self.imageViews(in: bubbleView).contains { $0.image === replacementImage })
    }

    func testContextMenuOmitsHistoryActionWhenThereAreNoRevisions() {
        let bubbleView = SentMessageBubbleView(text: "Hello")

        let menu = bubbleView.makeContextMenu(editHistoryCount: 0)

        XCTAssertEqual(menu.children.map(\.title), [
            String(localized: .chatCopy),
            String(localized: .chatResend),
            String(localized: .chatEditAndResend)
        ])
    }

    func testContextMenuIncludesHistoryActionWhenRevisionsExist() {
        let bubbleView = SentMessageBubbleView(text: "Hello")
        bubbleView.editHistoryCount = 2

        let menu = bubbleView.makeContextMenu(editHistoryCount: bubbleView.editHistoryCount)

        XCTAssertEqual(menu.children.map(\.title), [
            String(localized: .chatCopy),
            String(localized: .chatResend),
            String(localized: .chatEditAndResend),
            String(localized: .chatHistoryCountFormat(2))
        ])
    }

    private static func attachment(id: UUID, filename: String) -> ChatAttachment {
        ChatAttachment(
            id: id,
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
}
