//
//  ChatHistoryStoreTests.swift
//  UniLLMsTests
//
//  Covers chat history persistence ordering and message isolation.
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

    func testFetchMessagesKeepsSessionsIsolatedAndChronological() async throws {
        let firstSession = ChatSession(title: "First")
        let secondSession = ChatSession(title: "Second")
        let lateMessage = ChatMessage(
            role: .assistant,
            content: "Late",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let earlyMessage = ChatMessage(
            role: .user,
            content: "Early",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let otherMessage = ChatMessage(
            role: .user,
            content: "Other",
            createdAt: Date(timeIntervalSince1970: 5)
        )

        try await store.saveSession(firstSession)
        try await store.saveSession(secondSession)
        try await store.saveMessage(lateMessage, sessionID: firstSession.id)
        try await store.saveMessage(earlyMessage, sessionID: firstSession.id)
        try await store.saveMessage(otherMessage, sessionID: secondSession.id)

        let firstMessages = try await store.fetchMessages(sessionID: firstSession.id)
        let secondMessages = try await store.fetchMessages(sessionID: secondSession.id)

        XCTAssertEqual(firstMessages.map(\.id), [earlyMessage.id, lateMessage.id])
        XCTAssertEqual(secondMessages, [otherMessage])
    }

    func testToolCallMessagesPersistArgumentsAndOutputs() async throws {
        let session = ChatSession(title: "Tool Call")
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            toolCalls: [
                ChatToolCall(
                    id: "call_1",
                    toolID: "search",
                    arguments: #"{"query":"weather"}"#
                )
            ],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let toolMessage = ChatMessage(
            role: .tool,
            content: #"{"temperature":"20C"}"#,
            toolCallID: "call_1",
            createdAt: Date(timeIntervalSince1970: 10)
        )

        try await store.saveSession(session)
        try await store.saveMessages([assistantMessage, toolMessage], sessionID: session.id)

        let messages = try await store.fetchMessages(sessionID: session.id)

        XCTAssertEqual(messages, [assistantMessage, toolMessage])
        XCTAssertEqual(messages[0].toolCalls?.first?.arguments, #"{"query":"weather"}"#)
        XCTAssertEqual(messages[1].content, #"{"temperature":"20C"}"#)
    }

    func testChatMessageDecodingDefaultsMissingReasoningToEmptyString() throws {
        let messageID = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let payload: [String: Any] = [
            "id": messageID.uuidString,
            "role": "assistant",
            "content": "Legacy response",
            "createdAt": createdAt.timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate

        let message = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.id, messageID)
        XCTAssertEqual(message.reasoning, "")
    }

    func testDeleteSessionRemovesSessionAndMessages() async throws {
        let session = ChatSession(title: "Delete Me")
        let message = ChatMessage(role: .user, content: "Remove this")

        try await store.saveSession(session)
        try await store.saveMessage(message, sessionID: session.id)

        try await store.deleteSession(id: session.id)

        XCTAssertTrue(try await store.fetchSessions().isEmpty)
        XCTAssertTrue(try await store.fetchMessages(sessionID: session.id).isEmpty)
    }
}
