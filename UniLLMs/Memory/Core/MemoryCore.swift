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

nonisolated enum MemoryInjectionTimeRange: String, Codable, CaseIterable, Equatable {
    case all
    case last24Hours
    case last7Days
    case last30Days
    case last90Days
    case lastYear

    var title: String {
        switch self {
        case .all:
            return "All Time"
        case .last24Hours:
            return "Last 24 Hours"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        case .last90Days:
            return "Last 90 Days"
        case .lastYear:
            return "Last Year"
        }
    }

    fileprivate var timeInterval: TimeInterval? {
        switch self {
        case .all:
            return nil
        case .last24Hours:
            return 24 * 60 * 60
        case .last7Days:
            return 7 * 24 * 60 * 60
        case .last30Days:
            return 30 * 24 * 60 * 60
        case .last90Days:
            return 90 * 24 * 60 * 60
        case .lastYear:
            return 365 * 24 * 60 * 60
        }
    }
}

nonisolated struct MemoryInjectionSettings: Codable, Equatable {
    static let defaultMaximumMemories = 8
    static let maximumMemoryLimit = 50
    static let selectableMaximumMemories = [3, 5, 8, 12, 20]

    var isEnabled: Bool
    var timeRange: MemoryInjectionTimeRange
    var maximumMemories: Int?

    init(
        isEnabled: Bool = true,
        timeRange: MemoryInjectionTimeRange = .all,
        maximumMemories: Int? = Self.defaultMaximumMemories
    ) {
        self.isEnabled = isEnabled
        self.timeRange = timeRange
        self.maximumMemories = Self.clampedMaximumMemories(maximumMemories)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case timeRange
        case maximumMemories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        timeRange = try container.decodeIfPresent(
            MemoryInjectionTimeRange.self,
            forKey: .timeRange
        ) ?? .all
        if container.contains(.maximumMemories) {
            if try container.decodeNil(forKey: .maximumMemories) {
                maximumMemories = nil
            } else {
                maximumMemories = Self.clampedMaximumMemories(
                    try container.decode(Int.self, forKey: .maximumMemories)
                )
            }
        } else {
            maximumMemories = Self.defaultMaximumMemories
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(timeRange, forKey: .timeRange)
        if let maximumMemories {
            try container.encode(maximumMemories, forKey: .maximumMemories)
        } else {
            try container.encodeNil(forKey: .maximumMemories)
        }
    }

    var maximumMemoriesDescription: String {
        guard let maximumMemories else {
            return "No limit"
        }

        return maximumMemories == 1 ? "1 memory" : "\(maximumMemories) memories"
    }

    static func clampedMaximumMemories(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }

        return min(max(1, value), maximumMemoryLimit)
    }
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
    private let store: any MemoryStore
    private let settingsStore: any MemorySettingsStore

    init(
        store: any MemoryStore,
        settingsStore: any MemorySettingsStore = UserDefaultsMemorySettingsStore.shared
    ) {
        self.store = store
        self.settingsStore = settingsStore
    }

    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        let settings = settingsStore.loadInjectionSettings()
        guard settings.isEnabled else {
            return []
        }

        let memories = try await store.fetchMemories(scope: .user)
        let eligibleMemories = Self.memories(
            memories,
            in: settings.timeRange,
            referenceDate: Date()
        )
        let query = Self.retrievalQuery(from: context)
        let matchingMemories = Self.filteredMemories(eligibleMemories, matching: query)
        let candidates = matchingMemories.isEmpty ? eligibleMemories : matchingMemories
        let sortedMemories = Self.sortedForPresentation(candidates)
        guard let maximumMemories = settings.maximumMemories else {
            return sortedMemories
        }

        return Array(sortedMemories.prefix(maximumMemories))
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

    private static func memories(
        _ memories: [MemoryRecord],
        in timeRange: MemoryInjectionTimeRange,
        referenceDate: Date
    ) -> [MemoryRecord] {
        guard let timeInterval = timeRange.timeInterval else {
            return memories
        }

        let cutoffDate = referenceDate.addingTimeInterval(-timeInterval)
        return memories.filter {
            $0.updatedAt >= cutoffDate
        }
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
    private let settingsStore: any MemorySettingsStore
    private let retriever: any MemoryRetriever
    private let writer: any MemoryWriter
    private let policy: MemoryPolicy

    init(
        store: (any MemoryStore)? = nil,
        settingsStore: any MemorySettingsStore = UserDefaultsMemorySettingsStore.shared,
        retriever: (any MemoryRetriever)? = nil,
        writer: any MemoryWriter = EmptyMemoryWriter(),
        policy: MemoryPolicy = .default
    ) {
        self.store = store
        self.settingsStore = settingsStore
        if let retriever {
            self.retriever = retriever
        } else if let store {
            self.retriever = StoreBackedMemoryRetriever(
                store: store,
                settingsStore: settingsStore
            )
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

    func memoryInjectionSettings() -> MemoryInjectionSettings {
        settingsStore.loadInjectionSettings()
    }

    func saveMemoryInjectionSettings(_ settings: MemoryInjectionSettings) {
        settingsStore.saveInjectionSettings(settings)
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
