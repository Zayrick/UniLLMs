//
//  ChatMessageRevisionHistoryItemTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatMessageRevisionHistoryItemTests: XCTestCase {
    func testItemUsesFirstUserMessageAsSingleLineTitle() {
        let revision = makeRevision(events: [
            event(kind: .userMessage(text: "  Hello\nworld  ")),
            event(kind: .assistantContent(markdown: "Response"))
        ])

        let item = ChatMessageRevisionHistoryItem(
            revision: revision,
            dateFormatter: makeDateFormatter()
        )

        XCTAssertEqual(item.title, "Hello world")
        XCTAssertEqual(item.subtitle, "2026-01-02 03:04")
        XCTAssertEqual(item.followUpUserMessageCount, 0)
    }

    func testItemFallsBackToFirstAttachmentFilenameWhenUserTextIsEmpty() {
        let revision = makeRevision(events: [
            event(
                kind: .userMessageWithAttachments(
                    text: " \n ",
                    attachments: [
                        ChatAttachment(
                            id: UUID(),
                            kind: .image,
                            filename: " screenshot.png ",
                            contentType: "image/png",
                            relativePath: "attachments/screenshot.png"
                        )
                    ]
                )
            )
        ])

        let item = ChatMessageRevisionHistoryItem(
            revision: revision,
            dateFormatter: makeDateFormatter()
        )

        XCTAssertEqual(item.title, "screenshot.png")
    }

    func testItemFallsBackToLocalizedAttachmentTitleWhenNoTextOrFilenameExists() {
        let revision = makeRevision(events: [
            event(kind: .assistantContent(markdown: "Response"))
        ])

        let item = ChatMessageRevisionHistoryItem(
            revision: revision,
            dateFormatter: makeDateFormatter(),
            attachmentFallbackTitle: "Attachment"
        )

        XCTAssertEqual(item.title, "Attachment")
    }

    func testItemCountsOnlyUserMessagesAfterTheFirstUserMessage() {
        let revision = makeRevision(events: [
            event(kind: .assistantContent(markdown: "Earlier assistant")),
            event(kind: .userMessage(text: "Original")),
            event(kind: .assistantReasoning(text: "Thinking")),
            event(
                kind: .userMessageWithAttachments(
                    text: "",
                    attachments: [
                        ChatAttachment(
                            id: UUID(),
                            kind: .file,
                            filename: "note.txt",
                            contentType: "text/plain",
                            relativePath: "attachments/note.txt"
                        )
                    ]
                )
            ),
            event(kind: .toolEvent(.failed(
                ChatToolCall(id: "call_1", toolID: "search"),
                message: "No result"
            ))),
            event(kind: .userMessage(text: "Follow up"))
        ])

        let item = ChatMessageRevisionHistoryItem(
            revision: revision,
            dateFormatter: makeDateFormatter()
        )

        XCTAssertEqual(item.followUpUserMessageCount, 2)
    }

    private func makeRevision(events: [ChatTimelineEvent]) -> ChatMessageRevision {
        ChatMessageRevision(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            anchorUserMessageID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            archivedAt: makeArchivedDate(),
            events: events
        )
    }

    private func event(kind: ChatTimelineEvent.Kind) -> ChatTimelineEvent {
        ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: kind
        )
    }

    private func makeArchivedDate() -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 1,
            day: 2,
            hour: 3,
            minute: 4
        ).date!
    }

    private func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}
