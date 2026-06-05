//
//  ChatTimelinePresentationPlanTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatTimelinePresentationPlanTests: XCTestCase {
    func testPlanSortsEventsAndGroupsContinuousAssistantEvents() {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let toolCall = ChatToolCall(id: "call_1", toolID: "search")
        let events = [
            event(at: 4, kind: .assistantContent(markdown: "Answer")),
            event(at: 1, id: userID, kind: .userMessage(text: "Hello")),
            event(at: 3, kind: .assistantToolCalls([toolCall])),
            event(at: 2, kind: .assistantReasoning(text: "Thinking"))
        ]

        let plan = ChatTimelinePresentationPlan(events: events)

        XCTAssertEqual(plan.rows, [
            .userMessage(id: userID, text: "Hello", attachments: []),
            .assistantResponse(steps: [
                .reasoning("Thinking"),
                .toolEvent(.started(toolCall)),
                .contentMarkdown("Answer")
            ])
        ])
    }

    func testPlanStartsNewAssistantResponseAfterEachUserMessage() {
        let firstUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let secondUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let events = [
            event(at: 1, id: firstUserID, kind: .userMessage(text: "First")),
            event(at: 2, kind: .assistantContent(markdown: "First response")),
            event(at: 3, id: secondUserID, kind: .userMessage(text: "Second")),
            event(at: 4, kind: .assistantReasoning(text: "Second reasoning")),
            event(at: 5, kind: .assistantContent(markdown: "Second response"))
        ]

        let plan = ChatTimelinePresentationPlan(events: events)

        XCTAssertEqual(plan.rows, [
            .userMessage(id: firstUserID, text: "First", attachments: []),
            .assistantResponse(steps: [
                .contentMarkdown("First response")
            ]),
            .userMessage(id: secondUserID, text: "Second", attachments: []),
            .assistantResponse(steps: [
                .reasoning("Second reasoning"),
                .contentMarkdown("Second response")
            ])
        ])
    }

    func testPlanKeepsUserAttachmentsAndSkipsRevisionEvents() {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let attachment = ChatAttachment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            kind: .image,
            filename: "photo.jpg",
            contentType: "image/jpeg",
            relativePath: "attachments/photo.jpg"
        )
        let revision = ChatMessageRevision(
            anchorUserMessageID: userID,
            archivedAt: Date(timeIntervalSince1970: 1),
            events: [
                event(at: 0, kind: .userMessage(text: "Archived"))
            ]
        )
        let events = [
            event(at: 1, kind: .messageRevision(revision)),
            event(
                at: 2,
                id: userID,
                kind: .userMessageWithAttachments(text: "", attachments: [attachment])
            )
        ]

        let plan = ChatTimelinePresentationPlan(events: events)

        XCTAssertEqual(plan.rows, [
            .userMessage(id: userID, text: "", attachments: [attachment])
        ])
    }

    func testPlanKeepsStableOrderForEventsWithMatchingTimestamps() {
        let timestamp = Date(timeIntervalSince1970: 1)
        let firstUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let secondUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let events = [
            ChatTimelineEvent(id: firstUserID, timestamp: timestamp, kind: .userMessage(text: "First")),
            ChatTimelineEvent(id: secondUserID, timestamp: timestamp, kind: .userMessage(text: "Second"))
        ]

        let plan = ChatTimelinePresentationPlan(events: events)

        XCTAssertEqual(plan.rows, [
            .userMessage(id: firstUserID, text: "First", attachments: []),
            .userMessage(id: secondUserID, text: "Second", attachments: [])
        ])
    }

    private func event(
        at seconds: TimeInterval,
        id: UUID = UUID(),
        kind: ChatTimelineEvent.Kind
    ) -> ChatTimelineEvent {
        ChatTimelineEvent(
            id: id,
            timestamp: Date(timeIntervalSince1970: seconds),
            kind: kind
        )
    }
}
