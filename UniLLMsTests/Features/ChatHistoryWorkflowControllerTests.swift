//
//  ChatHistoryWorkflowControllerTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class ChatHistoryWorkflowControllerTests: XCTestCase {
    func testReloadSessionsFetchesSessionsWithSelectedID() async {
        let selectedID = UUID()
        let sessions = [
            makeTestChatSession(id: selectedID, title: "Selected"),
            makeTestChatSession(title: "Other")
        ]
        let store = CapturingWorkflowHistoryStore(sessions: sessions)
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var reloadedSessions: [ChatSession] = []
        var reloadedSelectedID: UUID?

        controller.reloadSessions(selectedSessionID: selectedID) { sessions, selectedSessionID in
            reloadedSessions = sessions
            reloadedSelectedID = selectedSessionID
        }
        await waitUntil { reloadedSessions.count == sessions.count }

        XCTAssertEqual(reloadedSessions, sessions)
        XCTAssertEqual(reloadedSelectedID, selectedID)
    }

    func testReloadSessionsReportsFetchFailureWithoutClearingHistory() async {
        let store = CapturingWorkflowHistoryStore(fetchSessionsError: WorkflowFailure.sample)
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var didReload = false
        var failureDescription: String?

        controller.reloadSessions(selectedSessionID: UUID()) { _, _ in
            didReload = true
        } didFail: { error in
            failureDescription = error.localizedDescription
        }
        await waitUntil { failureDescription != nil }

        XCTAssertFalse(didReload)
        XCTAssertEqual(failureDescription, WorkflowFailure.sample.localizedDescription)
    }

    func testSelectSessionIsIgnoredWhileResponseIsActive() {
        let store = CapturingWorkflowHistoryStore()
        let controller = ChatHistoryWorkflowController(historyStore: store)
        let session = makeTestChatSession(title: "Active")
        var rejectCount = 0

        let didStartSelection = controller.selectSession(
            session,
            isResponseActive: { true },
            didLoad: { _, _ in
                XCTFail("Selection should be ignored.")
            },
            didReject: {
                rejectCount += 1
            }
        )

        XCTAssertEqual(rejectCount, 1)
        XCTAssertFalse(didStartSelection)
        XCTAssertEqual(store.fetchEventsSessionIDs, [])
    }

    func testSelectSessionRevalidatesResponseActivityAfterFetchingEvents() async {
        let session = makeTestChatSession(title: "Saved")
        let event = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "Hello")
        )
        let store = SuspendedFetchEventsWorkflowHistoryStore(eventsBySessionID: [session.id: [event]])
        let controller = ChatHistoryWorkflowController(historyStore: store)
        let responseActivity = ResponseActivityProbe()
        var loadedSession: ChatSession?
        var rejectCount = 0

        let didStartSelection = controller.selectSession(
            session,
            isResponseActive: { responseActivity.isActive },
            didLoad: { session, _ in
                loadedSession = session
            },
            didReject: {
                rejectCount += 1
            }
        )
        await store.waitUntilFetchEventsStarted()
        responseActivity.isActive = true
        await store.resumeFetchEvents()
        await store.waitUntilFetchEventsReturned()
        await drainAsyncCallbacks()

        XCTAssertTrue(didStartSelection)
        XCTAssertNil(loadedSession)
        XCTAssertEqual(rejectCount, 1)
    }

    func testSelectSessionReportsEventFetchFailureWithoutLoadingEmptyTimeline() async {
        let session = makeTestChatSession(title: "Saved")
        let store = CapturingWorkflowHistoryStore(fetchEventsError: WorkflowFailure.sample)
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var loadedSession: ChatSession?
        var failureDescription: String?

        let didStartSelection = controller.selectSession(
            session,
            isResponseActive: { false }
        ) { session, _ in
            loadedSession = session
        } didFail: { error in
            failureDescription = error.localizedDescription
        }
        await waitUntil { failureDescription != nil }

        XCTAssertTrue(didStartSelection)
        XCTAssertNil(loadedSession)
        XCTAssertEqual(store.fetchEventsSessionIDs, [session.id])
        XCTAssertEqual(failureDescription, WorkflowFailure.sample.localizedDescription)
    }

    func testSelectSessionFetchesEvents() async {
        let session = makeTestChatSession(title: "Saved")
        let event = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "Hello")
        )
        let store = CapturingWorkflowHistoryStore(eventsBySessionID: [session.id: [event]])
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var loadedSession: ChatSession?
        var loadedEvents: [ChatTimelineEvent] = []

        let didStartSelection = controller.selectSession(
            session,
            isResponseActive: { false }
        ) { session, events in
            loadedSession = session
            loadedEvents = events
        }
        await waitUntil { loadedSession != nil }

        XCTAssertTrue(didStartSelection)
        XCTAssertEqual(loadedSession, session)
        XCTAssertEqual(loadedEvents, [event])
    }

    func testStartingDeleteCancelsPendingSelectionWithRejectOutcome() async {
        let selectedSession = makeTestChatSession(title: "Selected")
        let deletedSession = makeTestChatSession(title: "Deleted")
        let event = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "Hello")
        )
        let store = SuspendedFetchEventsWorkflowHistoryStore(
            eventsBySessionID: [selectedSession.id: [event]],
            deleteSessionError: WorkflowFailure.sample
        )
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var loadedSession: ChatSession?
        var selectionRejectCount = 0
        var deleteFailureDescription: String?

        let didStartSelection = controller.selectSession(
            selectedSession,
            isResponseActive: { false },
            didLoad: { session, _ in
                loadedSession = session
            },
            didReject: {
                selectionRejectCount += 1
            }
        )
        await store.waitUntilFetchEventsStarted()

        let didStartDelete = controller.deleteSession(
            deletedSession,
            currentSessionID: UUID(),
            isResponseActive: { false },
            currentSessionIDProvider: { selectedSession.id }
        ) { _ in
            XCTFail("Delete should fail.")
        } didFail: { error in
            deleteFailureDescription = error.localizedDescription
        }

        XCTAssertTrue(didStartSelection)
        XCTAssertTrue(didStartDelete)
        XCTAssertEqual(selectionRejectCount, 1)

        await waitUntil { deleteFailureDescription != nil }
        await store.resumeFetchEvents()
        await drainAsyncCallbacks()

        XCTAssertNil(loadedSession)
        XCTAssertEqual(selectionRejectCount, 1)
        XCTAssertEqual(deleteFailureDescription, WorkflowFailure.sample.localizedDescription)
    }

    func testStartingDeleteAfterCompletedSelectionDoesNotRejectCompletedSelection() async {
        let selectedSession = makeTestChatSession(title: "Selected")
        let deletedSession = makeTestChatSession(title: "Deleted")
        let event = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "Hello")
        )
        let store = CapturingWorkflowHistoryStore(eventsBySessionID: [selectedSession.id: [event]])
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var loadedSession: ChatSession?
        var selectionRejectCount = 0
        var deletionDecision: ChatHistoryActionPolicy.DeletionDecision?

        controller.selectSession(
            selectedSession,
            isResponseActive: { false },
            didLoad: { session, _ in
                loadedSession = session
            },
            didReject: {
                selectionRejectCount += 1
            }
        )
        await waitUntil { loadedSession != nil }

        controller.deleteSession(
            deletedSession,
            currentSessionID: selectedSession.id,
            isResponseActive: { false },
            currentSessionIDProvider: { selectedSession.id }
        ) { decision in
            deletionDecision = decision
        }
        await waitUntil { deletionDecision != nil }

        XCTAssertEqual(loadedSession, selectedSession)
        XCTAssertEqual(selectionRejectCount, 0)
        XCTAssertEqual(deletionDecision, .deleteOnly)
    }

    func testDeleteCurrentSessionIsIgnoredWhileResponseIsActive() {
        let session = makeTestChatSession(title: "Current")
        let store = CapturingWorkflowHistoryStore()
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var rejectCount = 0

        let didStartDelete = controller.deleteSession(
            session,
            currentSessionID: session.id,
            isResponseActive: { true },
            currentSessionIDProvider: { session.id }
        ) { _ in
            XCTFail("Delete should be ignored.")
        } didReject: {
            rejectCount += 1
        }

        XCTAssertEqual(rejectCount, 1)
        XCTAssertFalse(didStartDelete)
        XCTAssertEqual(store.deletedSessionIDs, [])
    }

    func testDeleteCurrentSessionReportsRejectWhenRevalidationIgnoresBeforeDeleting() async {
        let session = makeTestChatSession(title: "Current")
        let store = CapturingWorkflowHistoryStore()
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var responseActivityCheckCount = 0
        var deletionDecision: ChatHistoryActionPolicy.DeletionDecision?
        var rejectCount = 0

        let didStartDelete = controller.deleteSession(
            session,
            currentSessionID: session.id,
            isResponseActive: {
                responseActivityCheckCount += 1
                return responseActivityCheckCount > 1
            },
            currentSessionIDProvider: { session.id }
        ) { decision in
            deletionDecision = decision
        } didReject: {
            rejectCount += 1
        }
        await drainAsyncCallbacks()

        XCTAssertTrue(didStartDelete)
        XCTAssertNil(deletionDecision)
        XCTAssertEqual(rejectCount, 1)
        XCTAssertEqual(store.deletedSessionIDs, [])
    }

    func testDeleteUsesCurrentSessionIDAtCompletion() async {
        let deletedSession = makeTestChatSession(title: "Deleted")
        let replacementSession = makeTestChatSession(title: "Replacement")
        let store = CapturingWorkflowHistoryStore()
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var currentSessionID = deletedSession.id
        var deletionDecision: ChatHistoryActionPolicy.DeletionDecision?

        let didStartDelete = controller.deleteSession(
            deletedSession,
            currentSessionID: deletedSession.id,
            isResponseActive: { false },
            currentSessionIDProvider: { currentSessionID }
        ) { decision in
            deletionDecision = decision
        }
        currentSessionID = replacementSession.id
        await waitUntil { deletionDecision != nil }

        XCTAssertTrue(didStartDelete)
        XCTAssertEqual(store.deletedSessionIDs, [deletedSession.id])
        XCTAssertEqual(deletionDecision, .deleteOnly)
    }

    func testDeleteCurrentSessionRevalidatesResponseActivityAfterDeleting() async {
        let deletedSession = makeTestChatSession(title: "Deleted")
        let store = SuspendedDeleteWorkflowHistoryStore()
        let controller = ChatHistoryWorkflowController(historyStore: store)
        let responseActivity = ResponseActivityProbe()
        var deletionDecision: ChatHistoryActionPolicy.DeletionDecision?

        let didStartDelete = controller.deleteSession(
            deletedSession,
            currentSessionID: deletedSession.id,
            isResponseActive: { responseActivity.isActive },
            currentSessionIDProvider: { deletedSession.id }
        ) { decision in
            deletionDecision = decision
        }
        await store.waitUntilDeleteSessionStarted()
        responseActivity.isActive = true
        await store.resumeDeleteSession()
        await waitUntil { deletionDecision != nil }

        XCTAssertTrue(didStartDelete)
        let deletedSessionIDs = await store.deletedSessionIDs()
        XCTAssertEqual(deletedSessionIDs, [deletedSession.id])
        XCTAssertEqual(deletionDecision, .ignore)
    }

    func testDeleteSessionReportsFailureWithoutCompletingDelete() async {
        let session = makeTestChatSession(title: "Saved")
        let store = CapturingWorkflowHistoryStore(deleteSessionError: WorkflowFailure.sample)
        let controller = ChatHistoryWorkflowController(historyStore: store)
        var deletionDecision: ChatHistoryActionPolicy.DeletionDecision?
        var failureDescription: String?

        let didStartDelete = controller.deleteSession(
            session,
            currentSessionID: UUID(),
            isResponseActive: { false },
            currentSessionIDProvider: { session.id }
        ) { decision in
            deletionDecision = decision
        } didFail: { error in
            failureDescription = error.localizedDescription
        }
        await waitUntil { failureDescription != nil }

        XCTAssertTrue(didStartDelete)
        XCTAssertNil(deletionDecision)
        XCTAssertEqual(store.deletedSessionIDs, [])
        XCTAssertEqual(failureDescription, WorkflowFailure.sample.localizedDescription)
    }

    private func waitUntil(
        _ predicate: () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if predicate() {
                return
            }
            await Task.yield()
        }
    }

    private func drainAsyncCallbacks() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }
}

private final class CapturingWorkflowHistoryStore: ChatHistoryStore {
    private let sessions: [ChatSession]
    private let eventsBySessionID: [UUID: [ChatTimelineEvent]]
    private let fetchSessionsError: Error?
    private let fetchEventsError: Error?
    private let deleteSessionError: Error?
    private let lock = NSLock()
    private var capturedFetchEventsSessionIDs: [UUID] = []
    private var capturedDeletedSessionIDs: [UUID] = []

    init(
        sessions: [ChatSession] = [],
        eventsBySessionID: [UUID: [ChatTimelineEvent]] = [:],
        fetchSessionsError: Error? = nil,
        fetchEventsError: Error? = nil,
        deleteSessionError: Error? = nil
    ) {
        self.sessions = sessions
        self.eventsBySessionID = eventsBySessionID
        self.fetchSessionsError = fetchSessionsError
        self.fetchEventsError = fetchEventsError
        self.deleteSessionError = deleteSessionError
    }

    var fetchEventsSessionIDs: [UUID] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedFetchEventsSessionIDs
    }

    var deletedSessionIDs: [UUID] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedDeletedSessionIDs
    }

    func fetchSessions() async throws -> [ChatSession] {
        if let fetchSessionsError {
            throw fetchSessionsError
        }

        return sessions
    }

    func saveSession(_ session: ChatSession) async throws {}

    func deleteSession(id: UUID) async throws {
        if let deleteSessionError {
            throw deleteSessionError
        }

        withLock {
            capturedDeletedSessionIDs.append(id)
        }
    }

    func fetchEvents(sessionID: UUID) async throws -> [ChatTimelineEvent] {
        withLock {
            capturedFetchEventsSessionIDs.append(sessionID)
        }

        if let fetchEventsError {
            throw fetchEventsError
        }

        return eventsBySessionID[sessionID] ?? []
    }

    func saveEvent(_ event: ChatTimelineEvent, sessionID: UUID) async throws {}

    func saveEvents(_ events: [ChatTimelineEvent], sessionID: UUID) async throws {}

    private func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return try body()
    }
}

private final class SuspendedFetchEventsWorkflowHistoryStore: ChatHistoryStore {
    private let eventsBySessionID: [UUID: [ChatTimelineEvent]]
    private let deleteSessionError: Error?
    private let fetchEventsStartedGate = WorkflowAsyncGate()
    private let fetchEventsResumeGate = WorkflowAsyncGate()
    private let fetchEventsReturnedGate = WorkflowAsyncGate()

    init(
        eventsBySessionID: [UUID: [ChatTimelineEvent]],
        deleteSessionError: Error? = nil
    ) {
        self.eventsBySessionID = eventsBySessionID
        self.deleteSessionError = deleteSessionError
    }

    func waitUntilFetchEventsStarted() async {
        await fetchEventsStartedGate.wait()
    }

    func resumeFetchEvents() async {
        await fetchEventsResumeGate.open()
    }

    func waitUntilFetchEventsReturned() async {
        await fetchEventsReturnedGate.wait()
    }

    func fetchSessions() async throws -> [ChatSession] {
        []
    }

    func saveSession(_ session: ChatSession) async throws {}

    func deleteSession(id: UUID) async throws {
        if let deleteSessionError {
            throw deleteSessionError
        }
    }

    func fetchEvents(sessionID: UUID) async throws -> [ChatTimelineEvent] {
        await fetchEventsStartedGate.open()
        await fetchEventsResumeGate.wait()
        await fetchEventsReturnedGate.open()
        return eventsBySessionID[sessionID] ?? []
    }

    func saveEvent(_ event: ChatTimelineEvent, sessionID: UUID) async throws {}

    func saveEvents(_ events: [ChatTimelineEvent], sessionID: UUID) async throws {}
}

private final class SuspendedDeleteWorkflowHistoryStore: ChatHistoryStore {
    private let deleteStartedGate = WorkflowAsyncGate()
    private let deleteResumeGate = WorkflowAsyncGate()
    private let deletedSessionRecorder = WorkflowDeletedSessionRecorder()

    func deletedSessionIDs() async -> [UUID] {
        await deletedSessionRecorder.values
    }

    func waitUntilDeleteSessionStarted() async {
        await deleteStartedGate.wait()
    }

    func resumeDeleteSession() async {
        await deleteResumeGate.open()
    }

    func fetchSessions() async throws -> [ChatSession] {
        []
    }

    func saveSession(_ session: ChatSession) async throws {}

    func deleteSession(id: UUID) async throws {
        await deleteStartedGate.open()
        await deleteResumeGate.wait()
        await deletedSessionRecorder.append(id)
    }

    func fetchEvents(sessionID: UUID) async throws -> [ChatTimelineEvent] {
        []
    }

    func saveEvent(_ event: ChatTimelineEvent, sessionID: UUID) async throws {}

    func saveEvents(_ events: [ChatTimelineEvent], sessionID: UUID) async throws {}
}

@MainActor
private final class ResponseActivityProbe {
    var isActive = false
}

private actor WorkflowAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else {
            return
        }

        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private actor WorkflowDeletedSessionRecorder {
    private var recordedValues: [UUID] = []

    var values: [UUID] {
        recordedValues
    }

    func append(_ id: UUID) {
        recordedValues.append(id)
    }
}

private enum WorkflowFailure: LocalizedError {
    case sample

    var errorDescription: String? {
        "History unavailable."
    }
}
