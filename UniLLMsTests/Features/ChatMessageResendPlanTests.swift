//
//  ChatMessageResendPlanTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatMessageResendPlanTests: XCTestCase {
    func testMakeReturnsReplacementPlanForAvailableMessage() throws {
        let messageID = UUID()
        let attachment = ChatAttachment(
            kind: .image,
            filename: "photo.jpg",
            contentType: "image/jpeg",
            relativePath: "photo.jpg"
        )

        let decision = ChatMessageResendPlan.make(
            messageID: messageID,
            text: "Updated",
            attachments: [attachment],
            firstRemovedIndex: 3,
            isResponseActive: false
        )

        guard case let .resend(plan) = decision else {
            return XCTFail("Expected resend plan.")
        }
        XCTAssertEqual(plan.messageID, messageID)
        XCTAssertEqual(plan.text, "Updated")
        XCTAssertEqual(plan.attachments, [attachment])
        XCTAssertEqual(plan.firstRemovedIndex, 3)
        XCTAssertEqual(
            plan.presentationState,
            .replacementMessage(prompt: "Updated", attachments: [attachment])
        )
    }

    func testMakeIgnoresEmptyMessageWithoutAttachments() {
        XCTAssertEqual(
            ChatMessageResendPlan.make(
                messageID: UUID(),
                text: "",
                attachments: [],
                firstRemovedIndex: 0,
                isResponseActive: false
            ),
            .ignore
        )
    }

    func testMakeFailsDuringActiveResponse() {
        XCTAssertEqual(
            ChatMessageResendPlan.make(
                messageID: UUID(),
                text: "Updated",
                attachments: [],
                firstRemovedIndex: 0,
                isResponseActive: true
            ),
            .fail(.responseInProgress)
        )
    }

    func testMakeFailsWhenMessageIsUnavailable() {
        XCTAssertEqual(
            ChatMessageResendPlan.make(
                messageID: UUID(),
                text: "Updated",
                attachments: [],
                firstRemovedIndex: nil,
                isResponseActive: false
            ),
            .fail(.messageUnavailable)
        )
    }
}
