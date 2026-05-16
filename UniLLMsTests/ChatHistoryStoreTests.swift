//
//  ChatHistoryStoreTests.swift
//  UniLLMsTests
//
//  Covers chat history timeline persistence ordering and session isolation.
//  Created by Codex on 2026/5/14.
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: UserDefaultsChatStore!

    override func setUpWithError() throws {
        suiteName = "ChatHistoryStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = UserDefaultsChatStore(defaults: defaults, storageKey: "chatHistory")
    }

    override func tearDownWithError() throws {
        if let defaults, let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        store = nil
    }

    func testFetchSessionsSortsByLastSentDate() async throws {
        let olderSession = ChatSession(
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let newerSession = ChatSession(
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        try await store.saveSession(olderSession)
        try await store.saveSession(newerSession)

        let sessions = try await store.fetchSessions()

        XCTAssertEqual(sessions.map(\.id), [newerSession.id, olderSession.id])
    }

    func testFetchEventsKeepsSessionsIsolatedAndChronological() async throws {
        let firstSession = ChatSession(title: "First")
        let secondSession = ChatSession(title: "Second")
        let lateEvent = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 20),
            kind: .assistantContent(markdown: "Late")
        )
        let earlyEvent = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .userMessage(text: "Early")
        )
        let otherEvent = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 5),
            kind: .userMessage(text: "Other")
        )

        try await store.saveSession(firstSession)
        try await store.saveSession(secondSession)
        try await store.saveEvent(lateEvent, sessionID: firstSession.id)
        try await store.saveEvent(earlyEvent, sessionID: firstSession.id)
        try await store.saveEvent(otherEvent, sessionID: secondSession.id)

        let firstEvents = try await store.fetchEvents(sessionID: firstSession.id)
        let secondEvents = try await store.fetchEvents(sessionID: secondSession.id)

        XCTAssertEqual(firstEvents.map(\.id), [earlyEvent.id, lateEvent.id])
        XCTAssertEqual(secondEvents, [otherEvent])
    }

    func testToolTimelineEventsPersistArgumentsAndResults() async throws {
        let session = ChatSession(title: "Tool Call")
        let startedEvent = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .toolCallStarted(
                callID: "call_1",
                toolID: "search",
                displayName: "Weather Search",
                arguments: #"{"query":"weather"}"#
            )
        )
        let completedEvent = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 12),
            kind: .toolCallCompleted(
                callID: "call_1",
                toolID: "search",
                displayName: "Weather Search",
                result: #"{"temperature":"20C"}"#
            )
        )

        try await store.saveSession(session)
        try await store.saveEvents([completedEvent, startedEvent], sessionID: session.id)

        let events = try await store.fetchEvents(sessionID: session.id)

        XCTAssertEqual(events, [startedEvent, completedEvent])
    }

    func testTimelineAccumulatorMergesConsecutiveTextDeltas() {
        var accumulator = ChatTimelineAccumulator()
        let startedAt = Date(timeIntervalSince1970: 10)
        let continuedAt = Date(timeIntervalSince1970: 11)

        accumulator.appendDisplayDelta(
            ChatResponseDelta(reasoning: "Think "),
            timestamp: startedAt
        )
        accumulator.appendDisplayDelta(
            ChatResponseDelta(reasoning: "once"),
            timestamp: continuedAt
        )
        accumulator.appendDisplayDelta(
            ChatResponseDelta(content: "Answer "),
            timestamp: Date(timeIntervalSince1970: 12)
        )
        accumulator.appendDisplayDelta(
            ChatResponseDelta(content: "now"),
            timestamp: Date(timeIntervalSince1970: 13)
        )

        XCTAssertEqual(accumulator.events.map(\.timestamp), [startedAt, Date(timeIntervalSince1970: 12)])
        XCTAssertEqual(
            accumulator.events.map(\.kind),
            [
                .assistantReasoning(text: "Think once"),
                .assistantContent(markdown: "Answer now")
            ]
        )
    }

    func testTimelineEventsDeriveProviderMessages() {
        let events = [
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 1),
                kind: .userMessage(text: "Weather?")
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 2),
                kind: .assistantReasoning(text: "Need weather data.")
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 3),
                kind: .toolCallStarted(
                    callID: "call_1",
                    toolID: "search",
                    displayName: "Weather Search",
                    arguments: #"{"query":"weather"}"#
                )
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 4),
                kind: .toolCallCompleted(
                    callID: "call_1",
                    toolID: "search",
                    displayName: "Weather Search",
                    result: #"{"temperature":"20C"}"#
                )
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 5),
                kind: .assistantContent(markdown: "It is 20C.")
            )
        ]

        let messages = ChatTimelineEvent.messages(from: events)

        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .tool, .assistant])
        XCTAssertEqual(messages[0].content, "Weather?")
        XCTAssertEqual(messages[1].reasoning, "Need weather data.")
        XCTAssertEqual(messages[1].toolCalls?.first?.arguments, #"{"query":"weather"}"#)
        XCTAssertEqual(messages[2].toolCallID, "call_1")
        XCTAssertEqual(messages[2].content, #"{"temperature":"20C"}"#)
        XCTAssertEqual(messages[3].content, "It is 20C.")
    }

    func testDeleteSessionRemovesSessionAndEvents() async throws {
        let session = ChatSession(title: "Delete Me")
        let event = ChatTimelineEvent(kind: .userMessage(text: "Remove this"))

        try await store.saveSession(session)
        try await store.saveEvent(event, sessionID: session.id)

        try await store.deleteSession(id: session.id)

        XCTAssertTrue(try await store.fetchSessions().isEmpty)
        XCTAssertTrue(try await store.fetchEvents(sessionID: session.id).isEmpty)
    }
}
