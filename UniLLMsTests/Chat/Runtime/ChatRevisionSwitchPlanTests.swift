//
//  ChatRevisionSwitchPlanTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatRevisionSwitchPlanTests: XCTestCase {
    func testApplyRestoresSelectedRevisionAndArchivesCurrentBranch() throws {
        let anchorID = UUID()
        let selectedRevisionID = UUID()
        let firstUser = event(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "First")
        )
        let selectedRevision = ChatMessageRevision(
            id: selectedRevisionID,
            anchorUserMessageID: anchorID,
            archivedAt: Date(timeIntervalSince1970: 5),
            events: [
                event(
                    id: anchorID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    kind: .userMessage(text: "Original")
                ),
                event(
                    timestamp: Date(timeIntervalSince1970: 3),
                    kind: .assistantContent(markdown: "Original answer")
                )
            ]
        )
        let selectedRevisionEvent = event(
            timestamp: Date(timeIntervalSince1970: 5),
            kind: .messageRevision(selectedRevision)
        )
        let currentUser = event(
            id: anchorID,
            timestamp: Date(timeIntervalSince1970: 6),
            kind: .userMessage(text: "Edited")
        )
        let currentAssistant = event(
            timestamp: Date(timeIntervalSince1970: 7),
            kind: .assistantContent(markdown: "Edited answer")
        )
        let switchedAt = Date(timeIntervalSince1970: 10)
        let plan = ChatRevisionSwitchPlan(
            anchorUserMessageID: anchorID,
            revisionID: selectedRevisionID,
            switchedAt: switchedAt
        )

        let result = try XCTUnwrap(
            plan.apply(to: [
                selectedRevisionEvent,
                firstUser,
                currentUser,
                currentAssistant
            ])
        )

        XCTAssertEqual(result.sessionUpdatedAt, switchedAt)
        XCTAssertEqual(result.timeline.count, 4)
        XCTAssertEqual(result.timeline[0], firstUser)
        guard case let .messageRevision(currentRevision) = result.timeline[1].kind else {
            XCTFail("Expected current branch to be archived.")
            return
        }
        XCTAssertNotEqual(currentRevision.id, selectedRevisionID)
        XCTAssertEqual(currentRevision.anchorUserMessageID, anchorID)
        XCTAssertEqual(currentRevision.archivedAt, switchedAt)
        XCTAssertEqual(currentRevision.events.map(\.timelineEvent), [currentUser, currentAssistant])
        XCTAssertEqual(result.timeline[2], selectedRevision.events[0].timelineEvent)
        XCTAssertEqual(result.timeline[3], selectedRevision.events[1].timelineEvent)
    }

    func testApplyRetainsUnselectedRevisionEvents() throws {
        let anchorID = UUID()
        let selectedRevision = revision(
            id: UUID(),
            anchorUserMessageID: anchorID,
            text: "Original"
        )
        let retainedRevision = revision(
            id: UUID(),
            anchorUserMessageID: anchorID,
            text: "Older edit"
        )
        let currentUser = event(
            id: anchorID,
            timestamp: Date(timeIntervalSince1970: 6),
            kind: .userMessage(text: "Current")
        )
        let plan = ChatRevisionSwitchPlan(
            anchorUserMessageID: anchorID,
            revisionID: selectedRevision.id,
            switchedAt: Date(timeIntervalSince1970: 10)
        )

        let result = try XCTUnwrap(
            plan.apply(to: [
                event(timestamp: Date(timeIntervalSince1970: 4), kind: .messageRevision(selectedRevision)),
                event(timestamp: Date(timeIntervalSince1970: 5), kind: .messageRevision(retainedRevision)),
                currentUser
            ])
        )

        let revisions = ChatTimelineEvent.messageRevisions(from: result.timeline)[anchorID] ?? []
        XCTAssertEqual(revisions.count, 2)
        XCTAssertTrue(revisions.contains { $0.id == retainedRevision.id })
        XCTAssertFalse(revisions.contains { $0.id == selectedRevision.id })
        XCTAssertEqual(ChatTimelineEvent.messages(from: result.timeline).map(\.content), ["Original"])
    }

    func testApplyReturnsNilWhenSelectedRevisionIsMissing() {
        let anchorID = UUID()
        let plan = ChatRevisionSwitchPlan(
            anchorUserMessageID: anchorID,
            revisionID: UUID(),
            switchedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertNil(
            plan.apply(to: [
                event(
                    id: anchorID,
                    timestamp: Date(timeIntervalSince1970: 1),
                    kind: .userMessage(text: "Current")
                )
            ])
        )
    }

    func testApplyReturnsNilWhenAnchorIsNotOnCurrentMainline() {
        let anchorID = UUID()
        let selectedRevision = revision(
            id: UUID(),
            anchorUserMessageID: anchorID,
            text: "Original"
        )
        let plan = ChatRevisionSwitchPlan(
            anchorUserMessageID: anchorID,
            revisionID: selectedRevision.id,
            switchedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertNil(
            plan.apply(to: [
                event(
                    timestamp: Date(timeIntervalSince1970: 1),
                    kind: .messageRevision(selectedRevision)
                )
            ])
        )
    }

    private func revision(
        id: UUID,
        anchorUserMessageID: UUID,
        text: String
    ) -> ChatMessageRevision {
        ChatMessageRevision(
            id: id,
            anchorUserMessageID: anchorUserMessageID,
            archivedAt: Date(timeIntervalSince1970: 1),
            events: [
                event(
                    id: anchorUserMessageID,
                    timestamp: Date(timeIntervalSince1970: 2),
                    kind: .userMessage(text: text)
                )
            ]
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
