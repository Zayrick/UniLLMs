//
//  ChatHistoryPersistenceOperationPlanTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatHistoryPersistenceOperationPlanTests: XCTestCase {
    func testPrivacyModePlanRequiresNoStoreWrite() async throws {
        let session = makeTestChatSession(title: "Private")
        let events = [Self.userEvent(text: "Secret")]
        let plan = ChatHistoryPersistenceOperationPlan(
            session: session,
            events: events,
            privacyModeEnabled: true
        )
        let store = PlanHistoryStore()

        try await plan.perform(on: store)

        XCTAssertFalse(plan.requiresStoreWrite)
        XCTAssertNil(plan.storeOperation)
        XCTAssertEqual(store.operations, [])
    }

    func testEmptyNonPrivatePlanDeletesSession() async throws {
        let session = makeTestChatSession(title: "Empty")
        let plan = ChatHistoryPersistenceOperationPlan(
            session: session,
            events: [],
            privacyModeEnabled: false
        )
        let store = PlanHistoryStore()

        try await plan.perform(on: store)

        XCTAssertTrue(plan.requiresStoreWrite)
        XCTAssertEqual(plan.storeOperation, .deleteSession(session.id))
        XCTAssertEqual(store.operations, [.deleteSession(session.id)])
    }

    func testNonEmptyNonPrivatePlanSavesSessionBeforeEvents() async throws {
        let session = makeTestChatSession(title: "Persist")
        let events = [Self.userEvent(text: "Hello")]
        let plan = ChatHistoryPersistenceOperationPlan(
            session: session,
            events: events,
            privacyModeEnabled: false
        )
        let store = PlanHistoryStore()

        try await plan.perform(on: store)

        XCTAssertTrue(plan.requiresStoreWrite)
        XCTAssertEqual(plan.storeOperation, .saveSnapshot(session, events))
        XCTAssertEqual(
            store.operations,
            [
                .saveSession(session.id, title: "Persist"),
                .saveEvents(session.id, events)
            ]
        )
    }

    func testSaveEventsFailurePropagatesAfterSavingSession() async {
        let session = makeTestChatSession(title: "Persist")
        let events = [Self.userEvent(text: "Hello")]
        let plan = ChatHistoryPersistenceOperationPlan(
            session: session,
            events: events,
            privacyModeEnabled: false
        )
        let store = PlanHistoryStore(saveEventsError: PlanPersistenceFailure.sample)

        do {
            try await plan.perform(on: store)
            XCTFail("Expected save events failure.")
        } catch PlanPersistenceFailure.sample {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(store.operations, [.saveSession(session.id, title: "Persist")])
    }

    private static func userEvent(text: String) -> ChatTimelineEvent {
        ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: text)
        )
    }
}

private enum PlanHistoryOperation: Equatable {
    case deleteSession(UUID)
    case saveSession(UUID, title: String)
    case saveEvents(UUID, [ChatTimelineEvent])
}

private final class PlanHistoryStore: ChatHistoryStore {
    private(set) var operations: [PlanHistoryOperation] = []
    private let saveEventsError: Error?

    init(saveEventsError: Error? = nil) {
        self.saveEventsError = saveEventsError
    }

    func fetchSessions() async throws -> [ChatSession] {
        []
    }

    func saveSession(_ session: ChatSession) async throws {
        operations.append(.saveSession(session.id, title: session.title))
    }

    func deleteSession(id: UUID) async throws {
        operations.append(.deleteSession(id))
    }

    func fetchEvents(sessionID: UUID) async throws -> [ChatTimelineEvent] {
        []
    }

    func saveEvent(_ event: ChatTimelineEvent, sessionID: UUID) async throws {
        try await saveEvents([event], sessionID: sessionID)
    }

    func saveEvents(_ events: [ChatTimelineEvent], sessionID: UUID) async throws {
        if let saveEventsError {
            throw saveEventsError
        }

        operations.append(.saveEvents(sessionID, events))
    }
}

private enum PlanPersistenceFailure: Error {
    case sample
}
