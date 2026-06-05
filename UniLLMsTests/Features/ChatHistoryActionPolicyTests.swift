//
//  ChatHistoryActionPolicyTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatHistoryActionPolicyTests: XCTestCase {
    func testSelectionLoadsOnlyWhenResponseIsInactive() {
        XCTAssertEqual(
            ChatHistoryActionPolicy.selectionDecision(isResponseActive: false),
            .load
        )
        XCTAssertEqual(
            ChatHistoryActionPolicy.selectionDecision(isResponseActive: true),
            .ignore
        )
    }

    func testDeletionOfCurrentSessionResetsWhenResponseIsInactive() {
        let sessionID = UUID()

        XCTAssertEqual(
            ChatHistoryActionPolicy.deletionDecision(
                sessionID: sessionID,
                currentSessionID: sessionID,
                isResponseActive: false
            ),
            .deleteAndResetCurrent
        )
    }

    func testDeletionOfCurrentSessionIsIgnoredWhileResponseIsActive() {
        let sessionID = UUID()

        XCTAssertEqual(
            ChatHistoryActionPolicy.deletionDecision(
                sessionID: sessionID,
                currentSessionID: sessionID,
                isResponseActive: true
            ),
            .ignore
        )
    }

    func testDeletionOfOtherSessionIsAllowedWhileResponseIsActive() {
        XCTAssertEqual(
            ChatHistoryActionPolicy.deletionDecision(
                sessionID: UUID(),
                currentSessionID: UUID(),
                isResponseActive: true
            ),
            .deleteOnly
        )
    }

    func testDeletionCompletionUsesCurrentSessionAtCompletionTime() {
        let deletedSessionID = UUID()

        XCTAssertEqual(
            ChatHistoryActionPolicy.deletionCompletionDecision(
                sessionID: deletedSessionID,
                currentSessionID: deletedSessionID,
                isResponseActive: false
            ),
            .deleteAndResetCurrent
        )
        XCTAssertEqual(
            ChatHistoryActionPolicy.deletionCompletionDecision(
                sessionID: deletedSessionID,
                currentSessionID: UUID(),
                isResponseActive: false
            ),
            .deleteOnly
        )
        XCTAssertEqual(
            ChatHistoryActionPolicy.deletionCompletionDecision(
                sessionID: deletedSessionID,
                currentSessionID: deletedSessionID,
                isResponseActive: true
            ),
            .ignore
        )
    }
}
