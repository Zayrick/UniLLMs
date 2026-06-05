//
//  ChatMessageActionPolicyTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatMessageActionPolicyTests: XCTestCase {
    func testEditPresentationDecisionPrioritizesActiveResponse() {
        XCTAssertEqual(
            ChatMessageActionPolicy.editPresentationDecision(
                isResponseActive: true,
                isPresentingModal: false,
                containsMessage: true
            ),
            .fail(.responseInProgress)
        )
    }

    func testEditPresentationDecisionIgnoresWhenModalIsAlreadyPresented() {
        XCTAssertEqual(
            ChatMessageActionPolicy.editPresentationDecision(
                isResponseActive: false,
                isPresentingModal: true,
                containsMessage: true
            ),
            .ignore
        )
    }

    func testEditPresentationDecisionFailsWhenMessageIsUnavailable() {
        XCTAssertEqual(
            ChatMessageActionPolicy.editPresentationDecision(
                isResponseActive: false,
                isPresentingModal: false,
                containsMessage: false
            ),
            .fail(.messageUnavailable)
        )
    }

    func testRevisionHistoryDecisionRequiresMessageAndRevisions() {
        XCTAssertEqual(
            ChatMessageActionPolicy.revisionHistoryPresentationDecision(
                isPresentingModal: false,
                containsMessage: true,
                hasRevisions: true
            ),
            .present
        )
        XCTAssertEqual(
            ChatMessageActionPolicy.revisionHistoryPresentationDecision(
                isPresentingModal: false,
                containsMessage: true,
                hasRevisions: false
            ),
            .ignore
        )
        XCTAssertEqual(
            ChatMessageActionPolicy.revisionHistoryPresentationDecision(
                isPresentingModal: false,
                containsMessage: false,
                hasRevisions: true
            ),
            .fail(.messageUnavailable)
        )
    }

    func testRevisionSwitchDecisionBlocksDuringActiveResponse() {
        XCTAssertEqual(
            ChatMessageActionPolicy.revisionSwitchDecision(isResponseActive: true),
            .fail(.responseInProgress)
        )
        XCTAssertEqual(
            ChatMessageActionPolicy.revisionSwitchDecision(isResponseActive: false),
            .switchRevision
        )
    }

    func testEditedMessageTextTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(
            ChatMessageActionPolicy.editedMessageText("\n  Hello  \n"),
            "Hello"
        )
    }

    func testResendDecisionRequiresAvailableMessageAndContent() {
        XCTAssertEqual(
            ChatMessageActionPolicy.resendDecision(
                isResponseActive: false,
                text: "Hello",
                hasAttachments: false,
                containsMessage: true
            ),
            .resend
        )
        XCTAssertEqual(
            ChatMessageActionPolicy.resendDecision(
                isResponseActive: false,
                text: "",
                hasAttachments: true,
                containsMessage: true
            ),
            .resend
        )
        XCTAssertEqual(
            ChatMessageActionPolicy.resendDecision(
                isResponseActive: false,
                text: "",
                hasAttachments: false,
                containsMessage: true
            ),
            .ignore
        )
        XCTAssertEqual(
            ChatMessageActionPolicy.resendDecision(
                isResponseActive: false,
                text: "Hello",
                hasAttachments: false,
                containsMessage: false
            ),
            .fail(.messageUnavailable)
        )
        XCTAssertEqual(
            ChatMessageActionPolicy.resendDecision(
                isResponseActive: true,
                text: "Hello",
                hasAttachments: false,
                containsMessage: true
            ),
            .fail(.responseInProgress)
        )
    }
}
