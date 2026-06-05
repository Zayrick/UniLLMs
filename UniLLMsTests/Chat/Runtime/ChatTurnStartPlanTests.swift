//
//  ChatTurnStartPlanTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatTurnStartPlanTests: XCTestCase {
    func testApplyStartsFirstTurnWithPromptTitleAndRequestMessages() throws {
        let session = makeSession(
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let sentAt = Date(timeIntervalSince1970: 10)
        let userMessageID = UUID()
        let plan = ChatTurnStartPlan(
            prompt: "Hello\nworld",
            attachments: [],
            userMessageID: userMessageID,
            replacingUserMessageID: nil,
            sentAt: sentAt,
            emptyConversationTitle: "New Chat",
            attachmentFallbackTitle: "Attachment"
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: session,
                timeline: []
            )
        )

        XCTAssertEqual(result.session.title, "Hello world")
        XCTAssertEqual(result.session.createdAt, sentAt)
        XCTAssertEqual(result.session.updatedAt, sentAt)
        XCTAssertEqual(result.timeline, [result.userEvent])
        XCTAssertEqual(result.userEvent.id, userMessageID)
        XCTAssertEqual(result.userEvent.timestamp, sentAt)
        XCTAssertEqual(result.userEvent.kind, .userMessage(text: "Hello\nworld"))
        XCTAssertEqual(result.requestMessages.map(\.role), [.user])
        XCTAssertEqual(result.requestMessages.map(\.content), ["Hello\nworld"])
    }

    func testApplyStartsFirstTurnWithAttachmentTitleAndAttachmentEvent() throws {
        let attachment = makeAttachment(filename: "diagram.png")
        let sentAt = Date(timeIntervalSince1970: 10)
        let plan = ChatTurnStartPlan(
            prompt: "   ",
            attachments: [attachment],
            userMessageID: UUID(),
            replacingUserMessageID: nil,
            sentAt: sentAt,
            emptyConversationTitle: "New Chat",
            attachmentFallbackTitle: "Attachment"
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: makeSession(),
                timeline: []
            )
        )

        XCTAssertEqual(result.session.title, "diagram.png")
        XCTAssertEqual(
            result.userEvent.kind,
            .userMessageWithAttachments(text: "   ", attachments: [attachment])
        )
        XCTAssertEqual(result.requestMessages.first?.attachments, [attachment])
    }

    func testApplyDoesNotRetitleExistingConversation() throws {
        let existingUserEvent = event(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 8),
            kind: .userMessage(text: "Existing")
        )
        let session = makeSession(
            title: "Existing title",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 8)
        )
        let sentAt = Date(timeIntervalSince1970: 10)
        let plan = ChatTurnStartPlan(
            prompt: "New prompt",
            attachments: [],
            userMessageID: UUID(),
            replacingUserMessageID: nil,
            sentAt: sentAt,
            emptyConversationTitle: "New Chat",
            attachmentFallbackTitle: "Attachment"
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: session,
                timeline: [existingUserEvent]
            )
        )

        XCTAssertEqual(result.session.title, "Existing title")
        XCTAssertEqual(result.session.createdAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(result.session.updatedAt, sentAt)
        XCTAssertEqual(result.timeline.first, existingUserEvent)
        XCTAssertEqual(result.requestMessages.map(\.content), ["Existing", "New prompt"])
    }

    func testApplyArchivesCurrentBranchWhenReplacingUserMessage() throws {
        let replacedUserID = UUID()
        let firstUser = event(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "First")
        )
        let replacedUser = event(
            id: replacedUserID,
            timestamp: Date(timeIntervalSince1970: 2),
            kind: .userMessage(text: "Old")
        )
        let replacedAssistant = event(
            timestamp: Date(timeIntervalSince1970: 3),
            kind: .assistantContent(markdown: "Old answer")
        )
        let sentAt = Date(timeIntervalSince1970: 10)
        let plan = ChatTurnStartPlan(
            prompt: "New",
            attachments: [],
            userMessageID: replacedUserID,
            replacingUserMessageID: replacedUserID,
            sentAt: sentAt,
            emptyConversationTitle: "New Chat",
            attachmentFallbackTitle: "Attachment"
        )

        let result = try XCTUnwrap(
            plan.apply(
                to: makeSession(title: "Existing"),
                timeline: [firstUser, replacedUser, replacedAssistant]
            )
        )

        XCTAssertEqual(result.timeline.count, 3)
        XCTAssertEqual(result.timeline.first, firstUser)
        guard case let .messageRevision(revision) = result.timeline[1].kind else {
            XCTFail("Expected archived branch revision.")
            return
        }
        XCTAssertEqual(revision.anchorUserMessageID, replacedUserID)
        XCTAssertEqual(revision.archivedAt, sentAt)
        XCTAssertEqual(revision.events.map(\.timelineEvent), [replacedUser, replacedAssistant])
        XCTAssertEqual(result.timeline[2], result.userEvent)
        XCTAssertEqual(result.requestMessages.map(\.content), ["First", "New"])
        XCTAssertEqual(result.session.title, "Existing")
    }

    func testApplyReturnsNilWhenReplacementAnchorIsMissing() {
        let plan = ChatTurnStartPlan(
            prompt: "New",
            attachments: [],
            userMessageID: UUID(),
            replacingUserMessageID: UUID(),
            sentAt: Date(timeIntervalSince1970: 10),
            emptyConversationTitle: "New Chat",
            attachmentFallbackTitle: "Attachment"
        )

        XCTAssertNil(
            plan.apply(
                to: makeSession(),
                timeline: []
            )
        )
    }

    private func makeSession(
        title: String = "New Chat",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> ChatSession {
        ChatSession(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func makeAttachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            kind: .image,
            filename: filename,
            contentType: "image/png",
            relativePath: filename
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
