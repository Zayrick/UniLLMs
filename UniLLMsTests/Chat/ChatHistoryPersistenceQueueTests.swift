//
//  ChatHistoryPersistenceQueueTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class ChatHistoryPersistenceQueueTests: XCTestCase {
    func testPrivacySnapshotPostsNotificationWithoutWritingHistory() async {
        let notificationName = Notification.Name("ChatHistoryPersistenceQueueTests.privacy")
        let notificationCenter = NotificationCenter()
        let store = CapturingHistoryStore()
        let observer = NotificationObserver(
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )
        defer {
            observer.invalidate()
        }
        let queue = ChatHistoryPersistenceQueue(
            historyStore: store,
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )

        queue.persist(
            session: makeTestChatSession(title: "Private"),
            events: [Self.userEvent(text: "Secret")],
            privacyModeEnabled: true
        )
        await queue.waitForPendingPersistence()

        XCTAssertEqual(store.operations, [])
        XCTAssertEqual(observer.notificationCount, 1)
    }

    func testEmptySnapshotDeletesSessionAndPostsNotification() async {
        let notificationName = Notification.Name("ChatHistoryPersistenceQueueTests.empty")
        let notificationCenter = NotificationCenter()
        let store = CapturingHistoryStore()
        let observer = NotificationObserver(
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )
        defer {
            observer.invalidate()
        }
        let queue = ChatHistoryPersistenceQueue(
            historyStore: store,
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )
        let session = makeTestChatSession(title: "Empty")

        queue.persist(
            session: session,
            events: [],
            privacyModeEnabled: false
        )
        await queue.waitForPendingPersistence()

        XCTAssertEqual(store.operations, [.deleteSession(session.id)])
        XCTAssertEqual(observer.notificationCount, 1)
    }

    func testDeleteFailureReportsErrorWithoutPostingNotification() async {
        let notificationName = Notification.Name("ChatHistoryPersistenceQueueTests.deleteFailure")
        let notificationCenter = NotificationCenter()
        let store = CapturingHistoryStore(deleteSessionError: PersistenceFailure.sample)
        let observer = NotificationObserver(
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )
        defer {
            observer.invalidate()
        }
        var failureDescription: String?
        let queue = ChatHistoryPersistenceQueue(
            historyStore: store,
            notificationName: notificationName,
            notificationCenter: notificationCenter
        ) { error in
            failureDescription = error.localizedDescription
        }
        let session = makeTestChatSession(title: "Empty")

        queue.persist(
            session: session,
            events: [],
            privacyModeEnabled: false
        )
        await queue.waitForPendingPersistence()

        XCTAssertEqual(store.operations, [])
        XCTAssertEqual(observer.notificationCount, 0)
        XCTAssertEqual(failureDescription, PersistenceFailure.sample.localizedDescription)
    }

    func testSaveEventsFailureReportsErrorWithoutPostingNotification() async {
        let notificationName = Notification.Name("ChatHistoryPersistenceQueueTests.saveEventsFailure")
        let notificationCenter = NotificationCenter()
        let store = CapturingHistoryStore(saveEventsError: PersistenceFailure.sample)
        let observer = NotificationObserver(
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )
        defer {
            observer.invalidate()
        }
        var failureDescription: String?
        let queue = ChatHistoryPersistenceQueue(
            historyStore: store,
            notificationName: notificationName,
            notificationCenter: notificationCenter
        ) { error in
            failureDescription = error.localizedDescription
        }
        let session = makeTestChatSession(title: "Persist")
        let events = [Self.userEvent(text: "Hello")]

        queue.persist(
            session: session,
            events: events,
            privacyModeEnabled: false
        )
        await queue.waitForPendingPersistence()

        XCTAssertEqual(store.operations, [.saveSession(session.id, title: "Persist")])
        XCTAssertEqual(observer.notificationCount, 0)
        XCTAssertEqual(failureDescription, PersistenceFailure.sample.localizedDescription)
    }

    func testSnapshotsPersistSerially() async {
        let notificationName = Notification.Name("ChatHistoryPersistenceQueueTests.serial")
        let notificationCenter = NotificationCenter()
        let store = CapturingHistoryStore(suspendFirstSaveSession: true)
        let observer = NotificationObserver(
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )
        defer {
            observer.invalidate()
        }
        let queue = ChatHistoryPersistenceQueue(
            historyStore: store,
            notificationName: notificationName,
            notificationCenter: notificationCenter
        )
        let firstSession = makeTestChatSession(title: "First")
        let secondSession = makeTestChatSession(title: "Second")
        let firstEvents = [Self.userEvent(text: "First")]
        let secondEvents = [Self.userEvent(text: "Second")]

        queue.persist(
            session: firstSession,
            events: firstEvents,
            privacyModeEnabled: false
        )
        await store.waitForSuspendedSaveSession()

        queue.persist(
            session: secondSession,
            events: secondEvents,
            privacyModeEnabled: false
        )
        await Task.yield()

        XCTAssertEqual(store.saveSessionAttemptCount, 1)

        store.resumeSuspendedSaveSession()
        await queue.waitForPendingPersistence()

        XCTAssertEqual(
            store.operations,
            [
                .saveSession(firstSession.id, title: "First"),
                .saveEvents(firstSession.id, firstEvents),
                .saveSession(secondSession.id, title: "Second"),
                .saveEvents(secondSession.id, secondEvents)
            ]
        )
        XCTAssertEqual(observer.notificationCount, 2)
    }

    private static func userEvent(text: String) -> ChatTimelineEvent {
        ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: text)
        )
    }
}

private enum CapturedHistoryOperation: Equatable {
    case saveSession(UUID, title: String)
    case deleteSession(UUID)
    case saveEvents(UUID, [ChatTimelineEvent])
}

private final class CapturingHistoryStore: ChatHistoryStore {
    private let lock = NSLock()
    private let suspendFirstSaveSession: Bool
    private let deleteSessionError: Error?
    private let saveEventsError: Error?
    private var capturedOperations: [CapturedHistoryOperation] = []
    private var capturedSaveSessionAttemptCount = 0
    private var suspendedSaveSessionContinuation: CheckedContinuation<Void, Never>?

    init(
        suspendFirstSaveSession: Bool = false,
        deleteSessionError: Error? = nil,
        saveEventsError: Error? = nil
    ) {
        self.suspendFirstSaveSession = suspendFirstSaveSession
        self.deleteSessionError = deleteSessionError
        self.saveEventsError = saveEventsError
    }

    var operations: [CapturedHistoryOperation] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedOperations
    }

    var saveSessionAttemptCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedSaveSessionAttemptCount
    }

    func fetchSessions() async throws -> [ChatSession] {
        []
    }

    func saveSession(_ session: ChatSession) async throws {
        let shouldSuspend = registerSaveSessionAttempt()
        if shouldSuspend {
            await withCheckedContinuation { continuation in
                lock.lock()
                suspendedSaveSessionContinuation = continuation
                lock.unlock()
            }
        }

        append(.saveSession(session.id, title: session.title))
    }

    func deleteSession(id: UUID) async throws {
        if let deleteSessionError {
            throw deleteSessionError
        }

        append(.deleteSession(id))
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

        append(.saveEvents(sessionID, events))
    }

    func waitForSuspendedSaveSession() async {
        for _ in 0..<1_000 {
            let isSuspended = withLock {
                suspendedSaveSessionContinuation != nil
            }

            if isSuspended {
                return
            }

            await Task.yield()
        }
    }

    func resumeSuspendedSaveSession() {
        lock.lock()
        let continuation = suspendedSaveSessionContinuation
        suspendedSaveSessionContinuation = nil
        lock.unlock()

        continuation?.resume()
    }

    private func registerSaveSessionAttempt() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        capturedSaveSessionAttemptCount += 1
        return suspendFirstSaveSession && capturedSaveSessionAttemptCount == 1
    }

    private func append(_ operation: CapturedHistoryOperation) {
        lock.lock()
        capturedOperations.append(operation)
        lock.unlock()
    }

    private func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return try body()
    }
}

private enum PersistenceFailure: LocalizedError {
    case sample

    var errorDescription: String? {
        "History persistence failed."
    }
}

private final class NotificationObserver {
    private let notificationCenter: NotificationCenter
    private var token: NSObjectProtocol?
    private(set) var notificationCount = 0

    init(
        notificationName: Notification.Name,
        notificationCenter: NotificationCenter
    ) {
        self.notificationCenter = notificationCenter
        token = notificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.notificationCount += 1
        }
    }

    func invalidate() {
        if let token {
            notificationCenter.removeObserver(token)
        }
        token = nil
    }

    deinit {
        invalidate()
    }
}
