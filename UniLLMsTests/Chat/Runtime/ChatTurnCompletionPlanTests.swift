//
//  ChatTurnCompletionPlanTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatTurnCompletionPlanTests: XCTestCase {
    func testApplyAppendsProgressEventsAndAdvancesSessionTimestamp() throws {
        let turnID = UUID()
        let userEventID = UUID()
        let userEvent = event(
            id: userEventID,
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .userMessage(text: "Hello")
        )
        let progressEvent = event(
            timestamp: Date(timeIntervalSince1970: 20),
            kind: .assistantContent(markdown: "Done")
        )
        let plan = ChatTurnCompletionPlan(
            turnID: turnID,
            activeTurnID: turnID,
            userEventID: userEventID,
            progressEvents: [progressEvent],
            shouldKeepUserMessage: true
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: [userEvent],
                sessionUpdatedAt: Date(timeIntervalSince1970: 12)
            )
        )

        XCTAssertEqual(result.timeline, [userEvent, progressEvent])
        XCTAssertEqual(result.sessionUpdatedAt, Date(timeIntervalSince1970: 20))
    }

    func testApplyKeepsNewerSessionTimestampWhenProgressEventsAreOlder() throws {
        let turnID = UUID()
        let userEventID = UUID()
        let existingSessionUpdatedAt = Date(timeIntervalSince1970: 30)
        let progressEvent = event(
            timestamp: Date(timeIntervalSince1970: 20),
            kind: .assistantContent(markdown: "Done")
        )
        let plan = ChatTurnCompletionPlan(
            turnID: turnID,
            activeTurnID: turnID,
            userEventID: userEventID,
            progressEvents: [progressEvent],
            shouldKeepUserMessage: true
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: [],
                sessionUpdatedAt: existingSessionUpdatedAt
            )
        )

        XCTAssertEqual(result.timeline, [progressEvent])
        XCTAssertEqual(result.sessionUpdatedAt, existingSessionUpdatedAt)
    }

    func testApplyRemovesOptimisticUserMessageWhenTurnHasNoProgressAndShouldNotKeepMessage() throws {
        let turnID = UUID()
        let userEventID = UUID()
        let userEvent = event(
            id: userEventID,
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .userMessage(text: "Hello")
        )
        let existingEvent = event(
            timestamp: Date(timeIntervalSince1970: 8),
            kind: .assistantContent(markdown: "Earlier")
        )
        let plan = ChatTurnCompletionPlan(
            turnID: turnID,
            activeTurnID: turnID,
            userEventID: userEventID,
            progressEvents: [],
            shouldKeepUserMessage: false
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: [existingEvent, userEvent],
                sessionUpdatedAt: Date(timeIntervalSince1970: 12)
            )
        )

        XCTAssertEqual(result.timeline, [existingEvent])
        XCTAssertEqual(result.sessionUpdatedAt, Date(timeIntervalSince1970: 12))
    }

    func testApplyKeepsOptimisticUserMessageWhenRequested() throws {
        let turnID = UUID()
        let userEventID = UUID()
        let userEvent = event(
            id: userEventID,
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .userMessage(text: "Hello")
        )
        let plan = ChatTurnCompletionPlan(
            turnID: turnID,
            activeTurnID: turnID,
            userEventID: userEventID,
            progressEvents: [],
            shouldKeepUserMessage: true
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: [userEvent],
                sessionUpdatedAt: Date(timeIntervalSince1970: 12)
            )
        )

        XCTAssertEqual(result.timeline, [userEvent])
        XCTAssertEqual(result.sessionUpdatedAt, Date(timeIntervalSince1970: 12))
    }

    func testApplyIgnoresCompletionWhenTurnIsNotActive() {
        let plan = ChatTurnCompletionPlan(
            turnID: UUID(),
            activeTurnID: UUID(),
            userEventID: UUID(),
            progressEvents: [
                event(
                    timestamp: Date(timeIntervalSince1970: 20),
                    kind: .assistantContent(markdown: "Done")
                )
            ],
            shouldKeepUserMessage: true
        )

        XCTAssertNil(
            plan.apply(
                to: [],
                sessionUpdatedAt: Date(timeIntervalSince1970: 12)
            )
        )
    }

    private func event(
        id: UUID = UUID(),
        timestamp: Date,
        kind: ChatTimelineEvent.Kind
    ) -> ChatTimelineEvent {
        ChatTimelineEvent(
            id: id,
            timestamp: timestamp,
            kind: kind
        )
    }
}
