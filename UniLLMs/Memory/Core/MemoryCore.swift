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
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        scope: MemoryScope,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.scope = scope
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scope
        case text
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        scope = try container.decode(MemoryScope.self, forKey: .scope)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
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

struct StoreBackedMemoryRetriever: MemoryRetriever {
    private enum Defaults {
        static let maximumRetrievedMemories = 8
    }

    private let store: any MemoryStore

    init(store: any MemoryStore) {
        self.store = store
    }

    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        let memories = try await store.fetchMemories(scope: .user)
        let query = Self.retrievalQuery(from: context)
        let matchingMemories = Self.filteredMemories(memories, matching: query)
        let candidates = matchingMemories.isEmpty ? memories : matchingMemories
        return Array(Self.sortedForPresentation(candidates).prefix(Defaults.maximumRetrievedMemories))
    }

    private static func retrievalQuery(from context: ChatContext) -> String {
        context.messages.last(where: { $0.role == .user })?.content ?? ""
    }

    private static func filteredMemories(
        _ memories: [MemoryRecord],
        matching query: String
    ) -> [MemoryRecord] {
        let terms = searchTerms(from: query)
        guard !terms.isEmpty else {
            return memories
        }

        return memories.filter { memory in
            let searchableText = memory.text.lowercased()
            return terms.allSatisfy {
                searchableText.contains($0)
            }
        }
    }

    private static func searchTerms(from query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func sortedForPresentation(_ memories: [MemoryRecord]) -> [MemoryRecord] {
        memories.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.createdAt > $1.createdAt
        }
    }
}

enum MemoryManagerError: LocalizedError, Equatable {
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Memory storage is not available."
        }
    }
}

final class MemoryManager {
    private let store: (any MemoryStore)?
    private let retriever: any MemoryRetriever
    private let writer: any MemoryWriter
    private let policy: MemoryPolicy

    init(
        store: (any MemoryStore)? = nil,
        retriever: (any MemoryRetriever)? = nil,
        writer: any MemoryWriter = EmptyMemoryWriter(),
        policy: MemoryPolicy = .default
    ) {
        self.store = store
        if let retriever {
            self.retriever = retriever
        } else if let store {
            self.retriever = StoreBackedMemoryRetriever(store: store)
        } else {
            self.retriever = EmptyMemoryRetriever()
        }
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

    func savedMemories(scope: MemoryScope? = nil) async throws -> [MemoryRecord] {
        let store = try memoryStore
        let memories = try await store.fetchMemories(scope: scope)
        return sortedForPresentation(memories)
    }

    func memory(id: UUID) async throws -> MemoryRecord? {
        let memories = try await savedMemories()
        return memories.first {
            $0.id == id
        }
    }

    func makeMemoryDraft() -> MemoryRecord {
        MemoryRecord(scope: .user, text: "")
    }

    func saveMemory(_ memory: MemoryRecord) async throws {
        let store = try memoryStore
        try await store.saveMemory(memory)
    }

    @discardableResult
    func deleteMemory(id: UUID) async throws -> Bool {
        guard try await memory(id: id) != nil else {
            return false
        }

        let store = try memoryStore
        try await store.deleteMemory(id: id)
        return true
    }

    @discardableResult
    func deleteAllMemories(scope: MemoryScope? = nil) async throws -> Int {
        let deletedCount = try await savedMemories(scope: scope).count
        guard deletedCount > 0 else {
            return 0
        }

        let store = try memoryStore
        try await store.deleteMemories(scope: scope)
        return deletedCount
    }

    func searchMemories(
        query: String,
        scope: MemoryScope? = nil,
        limit: Int? = nil
    ) async throws -> [MemoryRecord] {
        let memories = try await savedMemories(scope: scope)
        let terms = Self.searchTerms(from: query)
        let matches: [MemoryRecord]
        if terms.isEmpty {
            matches = memories
        } else {
            matches = memories.filter { memory in
                let searchableText = memory.text.lowercased()
                return terms.allSatisfy {
                    searchableText.contains($0)
                }
            }
        }

        guard let limit else {
            return matches
        }

        return Array(matches.prefix(max(0, limit)))
    }

    private var memoryStore: any MemoryStore {
        get throws {
            guard let store else {
                throw MemoryManagerError.storageUnavailable
            }

            return store
        }
    }

    private func sortedForPresentation(_ memories: [MemoryRecord]) -> [MemoryRecord] {
        memories.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func searchTerms(from query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
