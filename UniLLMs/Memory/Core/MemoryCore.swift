//
//  MemoryCore.swift
//  UniLLMs
//
//  Defines memory records, retrieval, writing, policy, and empty manager implementations; currently a protocol boundary for future long-term memory.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated enum MemoryScope: String, Codable, Equatable {
    case user
    case session
}

nonisolated struct MemoryRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var scope: MemoryScope
    var text: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        scope: MemoryScope,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.text = text
        self.createdAt = createdAt
    }
}

nonisolated struct MemoryCandidate: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

nonisolated struct MemoryPolicy: Codable, Equatable {
    var requiresUserConfirmation: Bool

    static let `default` = MemoryPolicy(requiresUserConfirmation: true)
}

protocol MemoryRetriever {
    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord]
}

protocol MemoryWriter {
    func extractMemories(from session: ChatSession, messages: [ChatMessage]) async throws -> [MemoryCandidate]
}

struct EmptyMemoryRetriever: MemoryRetriever {
    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        []
    }
}

struct EmptyMemoryWriter: MemoryWriter {
    func extractMemories(from session: ChatSession, messages: [ChatMessage]) async throws -> [MemoryCandidate] {
        []
    }
}

final class MemoryManager {
    private let retriever: any MemoryRetriever
    private let writer: any MemoryWriter
    private let policy: MemoryPolicy

    init(
        retriever: any MemoryRetriever = EmptyMemoryRetriever(),
        writer: any MemoryWriter = EmptyMemoryWriter(),
        policy: MemoryPolicy = .default
    ) {
        self.retriever = retriever
        self.writer = writer
        self.policy = policy
    }

    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        try await retriever.retrieveRelevantMemories(for: context)
    }

    func extractCandidates(from session: ChatSession, messages: [ChatMessage]) async throws -> [MemoryCandidate] {
        guard policy.requiresUserConfirmation else {
            return try await writer.extractMemories(from: session, messages: messages)
        }

        return try await writer.extractMemories(from: session, messages: messages)
    }
}
