//
//  ChatStores.swift
//  UniLLMs
//
//  Defines chat session, message, and transcript export storage protocols; currently a persistence boundary for future chat history.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol ChatSessionStore {
    func fetchSessions() async throws -> [ChatSession]
    func saveSession(_ session: ChatSession) async throws
}

protocol ChatMessageStore {
    func fetchMessages(sessionID: UUID) async throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage, sessionID: UUID) async throws
}

protocol ChatTranscriptExporter {
    func export(session: ChatSession, messages: [ChatMessage]) throws -> Data
}
