//
//  ChatConversationTransitionPlanTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatConversationTransitionPlanTests: XCTestCase {
    func testResetCreatesNewEmptySessionAndEnablesRequestedPrivacyMode() {
        let now = Date(timeIntervalSince1970: 10)

        let result = ChatConversationTransitionPlan.reset(
            currentTimeline: [],
            wasPrivacyModeEnabled: false,
            privacyMode: true,
            now: now,
            emptyConversationTitle: "New Chat"
        )

        XCTAssertEqual(result.session.title, "New Chat")
        XCTAssertEqual(result.session.createdAt, now)
        XCTAssertEqual(result.session.updatedAt, now)
        XCTAssertTrue(result.timeline.isEmpty)
        XCTAssertTrue(result.privacyModeEnabled)
        XCTAssertTrue(result.discardedPrivateAttachments.isEmpty)
    }

    func testResetDiscardsAttachmentsOnlyFromPrivateConversation() {
        let attachment = makeAttachment(filename: "private.png")
        let currentTimeline = [
            event(
                timestamp: Date(timeIntervalSince1970: 1),
                kind: .userMessageWithAttachments(text: "Private", attachments: [attachment])
            )
        ]

        let privateResult = ChatConversationTransitionPlan.reset(
            currentTimeline: currentTimeline,
            wasPrivacyModeEnabled: true,
            privacyMode: false,
            now: Date(timeIntervalSince1970: 10),
            emptyConversationTitle: "New Chat"
        )
        let normalResult = ChatConversationTransitionPlan.reset(
            currentTimeline: currentTimeline,
            wasPrivacyModeEnabled: false,
            privacyMode: false,
            now: Date(timeIntervalSince1970: 10),
            emptyConversationTitle: "New Chat"
        )

        XCTAssertEqual(privateResult.discardedPrivateAttachments, [attachment])
        XCTAssertTrue(normalResult.discardedPrivateAttachments.isEmpty)
    }

    func testLoadSortsEventsAndClearsPrivacyMode() {
        let session = ChatSession(
            title: "Loaded",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        let laterEvent = event(
            timestamp: Date(timeIntervalSince1970: 3),
            kind: .assistantContent(markdown: "Later")
        )
        let earlierEvent = event(
            timestamp: Date(timeIntervalSince1970: 2),
            kind: .userMessage(text: "Earlier")
        )

        let result = ChatConversationTransitionPlan.load(
            session: session,
            events: [laterEvent, earlierEvent],
            currentTimeline: [],
            wasPrivacyModeEnabled: true
        )

        XCTAssertEqual(result.session, session)
        XCTAssertEqual(result.timeline, [earlierEvent, laterEvent])
        XCTAssertFalse(result.privacyModeEnabled)
    }

    func testLoadDiscardsCurrentPrivateAttachmentsBeforeReplacingTimeline() {
        let privateAttachment = makeAttachment(filename: "private.png")
        let loadedAttachment = makeAttachment(filename: "loaded.png")
        let currentTimeline = [
            event(
                timestamp: Date(timeIntervalSince1970: 1),
                kind: .userMessageWithAttachments(text: "Private", attachments: [privateAttachment])
            )
        ]
        let loadedTimeline = [
            event(
                timestamp: Date(timeIntervalSince1970: 2),
                kind: .userMessageWithAttachments(text: "Loaded", attachments: [loadedAttachment])
            )
        ]

        let result = ChatConversationTransitionPlan.load(
            session: ChatSession(
                title: "Loaded",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            events: loadedTimeline,
            currentTimeline: currentTimeline,
            wasPrivacyModeEnabled: true
        )

        XCTAssertEqual(result.discardedPrivateAttachments, [privateAttachment])
        XCTAssertEqual(ChatTimelineEvent.attachments(from: result.timeline), [loadedAttachment])
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
