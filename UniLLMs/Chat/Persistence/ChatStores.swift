//
//  ChatStores.swift
//  UniLLMs
//
//  Defines chat session, timeline, and transcript export storage protocols plus UserDefaults-backed chat history.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol ChatSessionStore {
    func fetchSessions() async throws -> [ChatSession]
    func saveSession(_ session: ChatSession) async throws
    func deleteSession(id: UUID) async throws
}

protocol ChatTimelineStore {
    func fetchEvents(sessionID: UUID) async throws -> [ChatTimelineEvent]
    func saveEvent(_ event: ChatTimelineEvent, sessionID: UUID) async throws
    func saveEvents(_ events: [ChatTimelineEvent], sessionID: UUID) async throws
}

protocol ChatTranscriptExporter {
    func export(session: ChatSession, events: [ChatTimelineEvent]) throws -> Data
}

typealias ChatHistoryStore = ChatSessionStore & ChatTimelineStore

struct ChatHistoryAttachmentCleanupFailure: LocalizedError {
    var removedAttachments: [ChatAttachment]
    var retainedAttachments: [ChatAttachment]
    var underlyingError: Error

    var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

final class UserDefaultsChatStore: ChatHistoryStore {
    static let attachmentCleanupDidCompleteNotification = Notification.Name(
        "UserDefaultsChatStoreAttachmentCleanupDidComplete"
    )
    static let attachmentCleanupDidFailNotification = Notification.Name(
        "UserDefaultsChatStoreAttachmentCleanupDidFail"
    )
    static let attachmentCleanupResultUserInfoKey = "result"
    static let attachmentCleanupFailureUserInfoKey = "failure"

    private struct Payload: Codable {
        var sessions: [ChatSession] = []
        var eventsBySessionID: [String: [ChatTimelineEvent]] = [:]
    }

    private let store: UserDefaultsStore
    private let notificationCenter: NotificationCenter
    private let storageKey: String
    private let attachmentStore: any ChatAttachmentCleanupStore
    private let attachmentCleanupDidFail: (ChatHistoryAttachmentCleanupFailure) -> Void

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        storageKey: String = "chatHistory",
        attachmentStore: any ChatAttachmentCleanupStore = ChatAttachmentStore.shared,
        attachmentCleanupDidFail: @escaping (ChatHistoryAttachmentCleanupFailure) -> Void = { _ in }
    ) {
        store = UserDefaultsStore(defaults: defaults, notificationCenter: notificationCenter)
        self.notificationCenter = notificationCenter
        self.storageKey = storageKey
        self.attachmentStore = attachmentStore
        self.attachmentCleanupDidFail = attachmentCleanupDidFail
    }

    func fetchSessions() async throws -> [ChatSession] {
        loadPayload().sessions.sorted(by: Self.sortSessionsByLastSentDate)
    }

    func saveSession(_ session: ChatSession) async throws {
        var payload = loadPayload()
        if let index = payload.sessions.firstIndex(where: { $0.id == session.id }) {
            payload.sessions[index] = session
        } else {
            payload.sessions.append(session)
        }
        try savePayload(payload)
    }

    func deleteSession(id: UUID) async throws {
        var payload = loadPayload()
        let removedEvents = payload.eventsBySessionID[id.uuidString] ?? []
        let retainedEvents = payload.eventsBySessionID
            .filter { $0.key != id.uuidString }
            .values
            .flatMap { $0 }
        payload.sessions.removeAll { $0.id == id }
        payload.eventsBySessionID[id.uuidString] = nil
        try savePayload(payload)
        cleanupUnreferencedAttachments(removing: removedEvents, retainedBy: retainedEvents)
    }

    func fetchEvents(sessionID: UUID) async throws -> [ChatTimelineEvent] {
        ChatTimelineEvent.sortedChronologically(loadPayload().eventsBySessionID[sessionID.uuidString] ?? [])
    }

    func saveEvent(_ event: ChatTimelineEvent, sessionID: UUID) async throws {
        var events = try await fetchEvents(sessionID: sessionID)
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        try await saveEvents(events, sessionID: sessionID)
    }

    func saveEvents(_ events: [ChatTimelineEvent], sessionID: UUID) async throws {
        var payload = loadPayload()
        let previousEvents = payload.eventsBySessionID[sessionID.uuidString] ?? []
        let storedEvents = ChatTimelineEvent.sortedChronologically(events)
        let retainedEvents = payload.eventsBySessionID
            .filter { $0.key != sessionID.uuidString }
            .values
            .flatMap { $0 } + storedEvents
        payload.eventsBySessionID[sessionID.uuidString] = storedEvents
        try savePayload(payload)
        cleanupUnreferencedAttachments(removing: previousEvents, retainedBy: retainedEvents)
    }

    private func loadPayload() -> Payload {
        store.load(Payload.self, forKey: storageKey) ?? Payload()
    }

    private func savePayload(_ payload: Payload) throws {
        try store.saveOrThrow(payload, forKey: storageKey)
    }

    private func cleanupUnreferencedAttachments(
        removing removedEvents: [ChatTimelineEvent],
        retainedBy retainedEvents: [ChatTimelineEvent]
    ) {
        let removedAttachments = ChatTimelineEvent.attachments(from: removedEvents)
        guard !removedAttachments.isEmpty else {
            return
        }

        let retainedAttachments = ChatTimelineEvent.attachments(from: retainedEvents)
        do {
            let result = try attachmentStore.deleteUnreferencedAttachments(
                removing: removedAttachments,
                referencedBy: retainedAttachments
            )
            guard !result.isEmpty else {
                return
            }

            notificationCenter.post(
                name: Self.attachmentCleanupDidCompleteNotification,
                object: self,
                userInfo: [Self.attachmentCleanupResultUserInfoKey: result]
            )
        } catch {
            let failure = ChatHistoryAttachmentCleanupFailure(
                removedAttachments: removedAttachments,
                retainedAttachments: retainedAttachments,
                underlyingError: error
            )
            attachmentCleanupDidFail(failure)
            notificationCenter.post(
                name: Self.attachmentCleanupDidFailNotification,
                object: self,
                userInfo: [Self.attachmentCleanupFailureUserInfoKey: failure]
            )
        }
    }

    private static func sortSessionsByLastSentDate(_ lhs: ChatSession, _ rhs: ChatSession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.createdAt > rhs.createdAt
    }
}
