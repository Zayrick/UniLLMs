//
//  ChatTimelineMessageBuilderTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatTimelineMessageBuilderTests: XCTestCase {
    func testBuilderSortsEventsAndFlushesAssistantBeforeUserMessage() {
        let firstUserID = UUID()
        let secondUserID = UUID()
        let events = [
            event(at: 3, id: secondUserID, kind: .userMessage(text: "Second")),
            event(at: 2, kind: .assistantContent(markdown: "First response")),
            event(at: 1, id: firstUserID, kind: .userMessage(text: "First"))
        ]

        let messages = ChatTimelineMessageBuilder.messages(from: events)

        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(messages.map(\.content), ["First", "First response", "Second"])
        XCTAssertEqual(messages[0].id, firstUserID)
        XCTAssertEqual(messages[2].id, secondUserID)
    }

    func testBuilderCombinesAssistantReasoningContentAndStartedToolCall() {
        let toolCall = ChatToolCall(id: "call_1", toolID: "search", displayName: "Search")
        let events = [
            event(at: 1, kind: .assistantReasoning(text: "Thinking ")),
            event(at: 2, kind: .assistantContent(markdown: "Answer")),
            event(at: 3, kind: .toolEvent(.started(toolCall)))
        ]

        let messages = ChatTimelineMessageBuilder.messages(from: events)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .assistant)
        XCTAssertEqual(messages[0].reasoning, "Thinking ")
        XCTAssertEqual(messages[0].content, "Answer")
        XCTAssertEqual(messages[0].toolCalls, [toolCall])
    }

    func testBuilderCreatesToolMessagesForCompletedAndFailedEvents() {
        let completedCall = ChatToolCall(id: "call_1", toolID: "search", displayName: "Search")
        let failedCall = ChatToolCall(id: "call_2", toolID: "calendar", displayName: "Calendar")
        let events = [
            event(at: 1, kind: .toolEvent(.completed(completedCall, result: "Sunny"))),
            event(at: 2, kind: .toolEvent(.failed(failedCall, message: "No access")))
        ]

        let messages = ChatTimelineMessageBuilder.messages(from: events)

        XCTAssertEqual(messages.map(\.role), [.tool, .tool])
        XCTAssertEqual(messages.map(\.toolCallID), ["call_1", "call_2"])
        XCTAssertEqual(messages.map(\.toolDisplayName), ["Search", "Calendar"])
        XCTAssertEqual(messages.map(\.toolStatus), [.success, .error])
        XCTAssertEqual(messages.map(\.content), ["Sunny", String(localized: .runtimeErrorToolExecutionFailedFormat("No access"))])
    }

    func testBuilderSkipsRevisionEvents() {
        let revision = ChatMessageRevision(
            anchorUserMessageID: UUID(),
            archivedAt: Date(timeIntervalSince1970: 1),
            events: [
                event(at: 1, kind: .userMessage(text: "Archived"))
            ]
        )
        let events = [
            event(at: 1, kind: .messageRevision(revision)),
            event(at: 2, kind: .userMessage(text: "Current"))
        ]

        let messages = ChatTimelineMessageBuilder.messages(from: events)

        XCTAssertEqual(messages.map(\.content), ["Current"])
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
