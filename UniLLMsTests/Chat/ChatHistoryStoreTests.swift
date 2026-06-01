//
//  ChatHistoryStoreTests.swift
//  UniLLMsTests
//
//  Covers chat history timeline persistence ordering and session isolation.
//  Created by Zayrick on 2026/5/14.
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: UserDefaultsChatStore!
    private var attachmentDirectory: URL!
    private var attachmentStore: ChatAttachmentStore!

    override func setUpWithError() throws {
        suiteName = "ChatHistoryStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        attachmentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        attachmentStore = ChatAttachmentStore(rootDirectory: attachmentDirectory)
        store = UserDefaultsChatStore(
            defaults: defaults,
            storageKey: "chatHistory",
            attachmentStore: attachmentStore
        )
    }

    override func tearDownWithError() throws {
        if let defaults, let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let attachmentDirectory,
           FileManager.default.fileExists(atPath: attachmentDirectory.path) {
            try? FileManager.default.removeItem(at: attachmentDirectory)
        }
        defaults = nil
        suiteName = nil
        store = nil
        attachmentDirectory = nil
        attachmentStore = nil
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

    func testSaveSessionPersistsSelectedSystemPromptID() async throws {
        let promptID = UUID()
        let session = ChatSession(
            title: "Prompted",
            selectedSystemPromptID: promptID
        )

        try await store.saveSession(session)

        let reloadedStore = UserDefaultsChatStore(
            defaults: defaults,
            storageKey: "chatHistory",
            attachmentStore: attachmentStore
        )
        let reloadedSessions = try await reloadedStore.fetchSessions()
        let reloadedSession = try XCTUnwrap(reloadedSessions.first { $0.id == session.id })
        XCTAssertEqual(reloadedSession.selectedSystemPromptID, promptID)
    }

    func testFetchSessionsDecodesLegacySessionsWithoutSelectedSystemPromptID() async throws {
        let sessionID = UUID()
        let legacyPayload = """
        {
          "sessions": [
            {
              "id": "\(sessionID.uuidString)",
              "title": "Legacy",
              "createdAt": "2026-05-20T12:00:00Z",
              "updatedAt": "2026-05-21T12:00:00Z"
            }
          ],
          "eventsBySessionID": {}
        }
        """
        defaults.set(try XCTUnwrap(legacyPayload.data(using: .utf8)), forKey: "chatHistory")

        let sessions = try await store.fetchSessions()

        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.id, sessionID)
        XCTAssertEqual(session.title, "Legacy")
        XCTAssertNil(session.selectedSystemPromptID)
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
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "search",
            arguments: #"{"query":"weather"}"#,
            displayName: "Weather Search"
        )
        let toolCallsEvent = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .assistantToolCalls([toolCall])
        )
        let completedEvent = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 12),
            kind: .toolEvent(.completed(toolCall, result: #"{"temperature":"20C"}"#))
        )

        try await store.saveSession(session)
        try await store.saveEvents([completedEvent, toolCallsEvent], sessionID: session.id)

        let events = try await store.fetchEvents(sessionID: session.id)

        XCTAssertEqual(events, [toolCallsEvent, completedEvent])
    }

    func testChatToolCallDecodesLegacyStringArguments() throws {
        let data = try XCTUnwrap(
            """
            {
              "id": "call_1",
              "toolID": "search",
              "arguments": "{\\"query\\":\\"weather\\"}",
              "displayName": "Weather Search"
            }
            """
            .data(using: .utf8)
        )

        let toolCall = try JSONDecoder().decode(ChatToolCall.self, from: data)

        XCTAssertEqual(toolCall.argumentObject, ["query": .string("weather")])
        XCTAssertEqual(toolCall.serializedArguments, #"{"query":"weather"}"#)
        XCTAssertEqual(toolCall.presentationName, "Weather Search")
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
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "search",
            arguments: #"{"query":"weather"}"#,
            displayName: "Weather Search"
        )
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
                kind: .assistantToolCalls([toolCall])
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 4),
                kind: .toolEvent(.completed(toolCall, result: #"{"temperature":"20C"}"#))
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
        XCTAssertEqual(messages[1].toolCalls?.first?.argumentObject, ["query": .string("weather")])
        XCTAssertEqual(messages[2].toolStatus, .success)
        XCTAssertEqual(messages[2].toolCallID, "call_1")
        XCTAssertEqual(messages[2].content, #"{"temperature":"20C"}"#)
        XCTAssertEqual(messages[3].content, "It is 20C.")
    }

    func testTimelineEventsKeepToolCallBatchTogether() {
        let firstToolCall = ChatToolCall(
            id: "call_1",
            toolID: "search",
            arguments: #"{"query":"weather"}"#,
            displayName: "Weather Search"
        )
        let secondToolCall = ChatToolCall(
            id: "call_2",
            toolID: "calendar",
            arguments: #"{"date":"today"}"#,
            displayName: "Calendar"
        )
        let events = [
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 1),
                kind: .userMessage(text: "Plan my day")
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 2),
                kind: .assistantToolCalls([firstToolCall, secondToolCall])
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 3),
                kind: .toolEvent(.completed(firstToolCall, result: "Sunny"))
            ),
            ChatTimelineEvent(
                timestamp: Date(timeIntervalSince1970: 4),
                kind: .toolEvent(.completed(secondToolCall, result: "No meetings"))
            )
        ]

        let messages = ChatTimelineEvent.messages(from: events)

        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .tool, .tool])
        XCTAssertEqual(messages[1].toolCalls?.map(\.id), ["call_1", "call_2"])
        XCTAssertEqual(messages[2].toolCallID, "call_1")
        XCTAssertEqual(messages[3].toolCallID, "call_2")
    }

    func testDeleteSessionRemovesSessionAndEvents() async throws {
        let session = ChatSession(title: "Delete Me")
        let event = ChatTimelineEvent(kind: .userMessage(text: "Remove this"))

        try await store.saveSession(session)
        try await store.saveEvent(event, sessionID: session.id)

        try await store.deleteSession(id: session.id)

        let sessions = try await store.fetchSessions()
        let events = try await store.fetchEvents(sessionID: session.id)

        XCTAssertTrue(sessions.isEmpty)
        XCTAssertTrue(events.isEmpty)
    }

    func testAttachmentStoreCreatesDistinctAttachmentsForDuplicateData() throws {
        let data = Data("same file bytes".utf8)

        let first = try attachmentStore.store(
            data: data,
            filename: "first.txt",
            kind: .file,
            contentType: "text/plain",
            preferredExtension: "txt"
        )
        let second = try attachmentStore.store(
            data: data,
            filename: "second.txt",
            kind: .file,
            contentType: "text/plain",
            preferredExtension: "txt"
        )

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.assetID, second.assetID)
        XCTAssertNotEqual(attachmentStore.fileURL(for: first), attachmentStore.fileURL(for: second))
        XCTAssertEqual(try attachmentStore.loadData(for: first), data)
        XCTAssertEqual(try attachmentStore.loadData(for: second), data)
    }

    func testSaveEventsRemovesAttachmentNoLongerReferencedBySession() async throws {
        let session = ChatSession(title: "Replacement")
        let attachment = try attachmentStore.store(
            data: Data("remove after replacement".utf8),
            filename: "replace.txt",
            kind: .file,
            contentType: "text/plain",
            preferredExtension: "txt"
        )
        let eventWithAttachment = ChatTimelineEvent(
            kind: .userMessageWithAttachments(text: "Attached", attachments: [attachment])
        )
        let replacementEvent = ChatTimelineEvent(kind: .userMessage(text: "No attachment"))

        try await store.saveSession(session)
        try await store.saveEvents([eventWithAttachment], sessionID: session.id)
        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))

        try await store.saveEvents([replacementEvent], sessionID: session.id)

        XCTAssertNil(attachmentStore.fileURL(for: attachment))
    }

    func testSaveEventsKeepsAttachmentReferencedByMessageRevision() async throws {
        let session = ChatSession(title: "Revision Attachment")
        let messageID = UUID()
        let attachment = try attachmentStore.store(
            data: Data("archived attachment".utf8),
            filename: "archived.txt",
            kind: .file,
            contentType: "text/plain",
            preferredExtension: "txt"
        )
        let archivedMessage = ChatTimelineEvent(
            id: messageID,
            kind: .userMessageWithAttachments(text: "Original", attachments: [attachment])
        )
        let replacementMessage = ChatTimelineEvent(
            id: messageID,
            kind: .userMessage(text: "Edited")
        )
        let revisionEvent = ChatTimelineEvent(
            kind: .messageRevision(
                ChatMessageRevision(
                    anchorUserMessageID: messageID,
                    events: [archivedMessage]
                )
            )
        )

        try await store.saveSession(session)
        try await store.saveEvents([revisionEvent, replacementMessage], sessionID: session.id)

        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))

        try await store.saveEvents([replacementMessage], sessionID: session.id)

        XCTAssertNil(attachmentStore.fileURL(for: attachment))
    }

    func testDeleteSessionRemovesUnreferencedAttachmentFile() async throws {
        let session = ChatSession(title: "Attachment")
        let attachment = try attachmentStore.store(
            data: Data("delete me".utf8),
            filename: "delete.txt",
            kind: .file,
            contentType: "text/plain",
            preferredExtension: "txt"
        )
        let event = ChatTimelineEvent(
            kind: .userMessageWithAttachments(text: "See attached", attachments: [attachment])
        )

        try await store.saveSession(session)
        try await store.saveEvent(event, sessionID: session.id)
        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))

        try await store.deleteSession(id: session.id)

        XCTAssertNil(attachmentStore.fileURL(for: attachment))
    }

    func testDeleteSessionKeepsAttachmentFileReferencedByAnotherSession() async throws {
        let firstSession = ChatSession(title: "First")
        let secondSession = ChatSession(title: "Second")
        let attachment = try attachmentStore.store(
            data: Data("shared".utf8),
            filename: "shared.txt",
            kind: .file,
            contentType: "text/plain",
            preferredExtension: "txt"
        )
        let firstEvent = ChatTimelineEvent(
            kind: .userMessageWithAttachments(text: "First", attachments: [attachment])
        )
        let secondAttachmentReference = ChatAttachment(
            assetID: attachment.assetID,
            kind: attachment.kind,
            filename: attachment.filename,
            contentType: attachment.contentType,
            relativePath: attachment.relativePath
        )
        let secondEvent = ChatTimelineEvent(
            kind: .userMessageWithAttachments(text: "Second", attachments: [secondAttachmentReference])
        )

        try await store.saveSession(firstSession)
        try await store.saveSession(secondSession)
        try await store.saveEvent(firstEvent, sessionID: firstSession.id)
        try await store.saveEvent(secondEvent, sessionID: secondSession.id)

        XCTAssertNotEqual(attachment.id, secondAttachmentReference.id)

        try await store.deleteSession(id: firstSession.id)

        XCTAssertNotNil(attachmentStore.fileURL(for: attachment))

        try await store.deleteSession(id: secondSession.id)

        XCTAssertNil(attachmentStore.fileURL(for: attachment))
    }
}
