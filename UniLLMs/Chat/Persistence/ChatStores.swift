//
//  ChatStores.swift
//  UniLLMs
//
//  Defines chat session, message, and transcript export storage protocols plus UserDefaults-backed chat history.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol ChatSessionStore {
    func fetchSessions() async throws -> [ChatSession]
    func saveSession(_ session: ChatSession) async throws
    func deleteSession(id: UUID) async throws
}

protocol ChatMessageStore {
    func fetchMessages(sessionID: UUID) async throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage, sessionID: UUID) async throws
    func saveMessages(_ messages: [ChatMessage], sessionID: UUID) async throws
}

protocol ChatTranscriptExporter {
    func export(session: ChatSession, messages: [ChatMessage]) throws -> Data
}

typealias ChatHistoryStore = ChatSessionStore & ChatMessageStore

final class UserDefaultsChatStore: ChatHistoryStore {
    private struct Payload: Codable {
        var sessions: [ChatSession] = []
        var messagesBySessionID: [String: [ChatMessage]] = [:]
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
        payload.messagesBySessionID[id.uuidString] = nil
        savePayload(payload)
    }

    func fetchMessages(sessionID: UUID) async throws -> [ChatMessage] {
        ChatMessage.sortedChronologically(loadPayload().messagesBySessionID[sessionID.uuidString] ?? [])
    }

    func saveMessage(_ message: ChatMessage, sessionID: UUID) async throws {
        var messages = try await fetchMessages(sessionID: sessionID)
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        try await saveMessages(messages, sessionID: sessionID)
    }

    func saveMessages(_ messages: [ChatMessage], sessionID: UUID) async throws {
        var payload = loadPayload()
        payload.messagesBySessionID[sessionID.uuidString] = ChatMessage.sortedChronologically(messages)
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
