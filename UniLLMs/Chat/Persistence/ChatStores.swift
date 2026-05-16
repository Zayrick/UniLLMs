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

final class UserDefaultsChatStore: ChatHistoryStore {
    private struct Payload: Codable {
        var sessions: [ChatSession] = []
        var eventsBySessionID: [String: [ChatTimelineEvent]] = [:]
    }

    private let store: UserDefaultsStore
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "chatHistory"
    ) {
        store = UserDefaultsStore(defaults: defaults)
        self.storageKey = storageKey
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
        savePayload(payload)
    }

    func deleteSession(id: UUID) async throws {
        var payload = loadPayload()
        payload.sessions.removeAll { $0.id == id }
        payload.eventsBySessionID[id.uuidString] = nil
        savePayload(payload)
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
        payload.eventsBySessionID[sessionID.uuidString] = ChatTimelineEvent.sortedChronologically(events)
        savePayload(payload)
    }

    private func loadPayload() -> Payload {
        store.load(Payload.self, forKey: storageKey) ?? Payload()
    }

    private func savePayload(_ payload: Payload) {
        store.save(payload, forKey: storageKey)
    }

    private static func sortSessionsByLastSentDate(_ lhs: ChatSession, _ rhs: ChatSession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.createdAt > rhs.createdAt
    }
}
