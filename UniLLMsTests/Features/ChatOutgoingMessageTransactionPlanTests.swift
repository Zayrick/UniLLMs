//
//  ChatOutgoingMessageTransactionPlanTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatOutgoingMessageTransactionPlanTests: XCTestCase {
    func testNewMessagePlanUsesComposerSendPresentation() {
        let messageID = UUID()
        let attachment = makeAttachment()

        let plan = ChatOutgoingMessageTransactionPlan.newMessage(
            text: "Hello",
            attachments: [attachment],
            messageID: messageID
        )

        XCTAssertEqual(plan.messageID, messageID)
        XCTAssertEqual(plan.prompt, "Hello")
        XCTAssertEqual(plan.attachments, [attachment])
        XCTAssertNil(plan.replacingUserMessageID)
        XCTAssertNil(plan.firstRemovedIndex)
        XCTAssertEqual(plan.initialBubbleAlpha, 0.0)
        XCTAssertEqual(
            plan.presentationState,
            .newMessage(prompt: "Hello", attachments: [attachment])
        )
        XCTAssertTrue(plan.consumesComposerAttachments)
        XCTAssertFalse(plan.refreshesEditHistory)
        XCTAssertEqual(plan.loadingPresentation, .afterSendAnimation)
    }

    func testReplacementPlanUsesResendPresentation() {
        let messageID = UUID()
        let attachment = makeAttachment()
        let resendPlan = ChatMessageResendPlan(
            messageID: messageID,
            text: "Edited",
            attachments: [attachment],
            firstRemovedIndex: 4,
            presentationState: .replacementMessage(
                prompt: "Edited",
                attachments: [attachment]
            )
        )

        let plan = ChatOutgoingMessageTransactionPlan.replacement(resendPlan: resendPlan)

        XCTAssertEqual(plan.messageID, messageID)
        XCTAssertEqual(plan.prompt, "Edited")
        XCTAssertEqual(plan.attachments, [attachment])
        XCTAssertEqual(plan.replacingUserMessageID, messageID)
        XCTAssertEqual(plan.firstRemovedIndex, 4)
        XCTAssertEqual(plan.initialBubbleAlpha, 1.0)
        XCTAssertEqual(
            plan.presentationState,
            .replacementMessage(prompt: "Edited", attachments: [attachment])
        )
        XCTAssertFalse(plan.consumesComposerAttachments)
        XCTAssertTrue(plan.refreshesEditHistory)
        XCTAssertEqual(plan.loadingPresentation, .immediately)
    }

    private func makeAttachment() -> ChatAttachment {
        ChatAttachment(
            kind: .file,
            filename: "notes.txt",
            contentType: "text/plain",
            relativePath: "notes.txt"
        )
    }
}
