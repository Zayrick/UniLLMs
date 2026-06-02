//
//  MemoryCore.swift
//  UniLLMs
//
//  Defines memory records, injection settings, retrieval/writing boundaries, and the manager used by chat and memory tools.
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

nonisolated enum MemoryInjectionFilter: String, Codable, CaseIterable, Equatable {
    case smart
    case all
    case last24Hours
    case last7Days
    case last30Days
    case last90Days
    case lastYear

    var title: String {
        switch self {
        case .smart:
            return String(localized: .memoriesFilterSmart)
        case .all:
            return String(localized: .memoriesFilterAllTime)
        case .last24Hours:
            return String(localized: .memoriesFilterLast24Hours)
        case .last7Days:
            return String(localized: .memoriesFilterLast7Days)
        case .last30Days:
            return String(localized: .memoriesFilterLast30Days)
        case .last90Days:
            return String(localized: .memoriesFilterLast90Days)
        case .lastYear:
            return String(localized: .memoriesFilterLastYear)
        }
    }

    fileprivate var timeInterval: TimeInterval? {
        switch self {
        case .smart, .all:
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
    static let defaultMaximumMemories = 5
    static let maximumMemoryLimit = 50
    static let selectableMaximumMemories = [3, 5, 8, 12, 20]

    var isEnabled: Bool
    var filter: MemoryInjectionFilter
    var maximumMemories: Int?

    init(
        isEnabled: Bool = true,
        filter: MemoryInjectionFilter = .smart,
        maximumMemories: Int? = Self.defaultMaximumMemories
    ) {
        self.isEnabled = isEnabled
        self.filter = filter
        self.maximumMemories = Self.clampedMaximumMemories(maximumMemories)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case filter
        case maximumMemories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        filter = try container.decodeIfPresent(
            MemoryInjectionFilter.self,
            forKey: .filter
        ) ?? .smart
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
        try container.encode(filter, forKey: .filter)
        if let maximumMemories {
            try container.encode(maximumMemories, forKey: .maximumMemories)
        } else {
            try container.encodeNil(forKey: .maximumMemories)
        }
    }

    static func clampedMaximumMemories(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }

        return min(max(1, value), maximumMemoryLimit)
    }
}

nonisolated enum MemoryTextSearch {
    private struct RelevanceToken: Hashable {
        enum Kind: Hashable {
            case word
            case cjkBigram
        }

        var kind: Kind
        var value: String
    }

    private static let promptStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "can", "could", "do", "does", "for", "from",
        "help", "how", "i", "in", "is", "it", "me", "my", "of", "on", "or", "please", "should",
        "the", "to", "with", "you", "your", "we", "what", "when", "where", "why", "would"
    ]

    private static let promptStopCharacters = Set(
        "你我他她它们的地得是了在和与及也有就都很更请帮做问说给能会想吗呢吧啊呀哦".unicodeScalars
    )

    static func filtered(
        _ memories: [MemoryRecord],
        matching query: String,
        emptyQueryMatchesAll: Bool = true
    ) -> [MemoryRecord] {
        let terms = searchTerms(from: query)
        guard !terms.isEmpty else {
            return emptyQueryMatchesAll ? memories : []
        }

        return memories.filter { memory in
            let searchableText = memory.text.lowercased()
            return terms.allSatisfy {
                searchableText.contains($0)
            }
        }
    }

    static func rankedByRelevance(_ memories: [MemoryRecord], matching query: String) -> [MemoryRecord] {
        let queryTokens = Array(Set(relevanceTokens(from: query, droppingPromptStopWords: true)))
        guard !queryTokens.isEmpty else {
            return []
        }

        return memories
            .map { memory in
                (
                    memory: memory,
                    score: relevanceScore(for: memory.text, queryTokens: queryTokens)
                )
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.memory.updatedAt != $1.memory.updatedAt {
                    return $0.memory.updatedAt > $1.memory.updatedAt
                }
                return $0.memory.createdAt > $1.memory.createdAt
            }
            .map(\.memory)
    }

    private static func searchTerms(from query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func relevanceScore(for text: String, queryTokens: [RelevanceToken]) -> Int {
        let frequencies = Dictionary(
            relevanceTokens(from: text, droppingPromptStopWords: false).map { ($0, 1) },
            uniquingKeysWith: +
        )

        return queryTokens.reduce(0) { score, token in
            score + (frequencies[token] ?? 0)
        }
    }

    private static func relevanceTokens(
        from text: String,
        droppingPromptStopWords: Bool
    ) -> [RelevanceToken] {
        var tokens: [RelevanceToken] = []
        var currentWord = ""
        var currentCJKScalars: [Unicode.Scalar] = []

        func appendCurrentWord() {
            guard !currentWord.isEmpty else {
                return
            }
            defer {
                currentWord = ""
            }

            guard !droppingPromptStopWords || !promptStopWords.contains(currentWord) else {
                return
            }

            tokens.append(RelevanceToken(kind: .word, value: currentWord))
        }

        func appendCurrentCJKRun() {
            guard currentCJKScalars.count >= 2 else {
                currentCJKScalars.removeAll()
                return
            }
            defer {
                currentCJKScalars.removeAll()
            }

            for index in currentCJKScalars.indices.dropLast() {
                let nextIndex = currentCJKScalars.index(after: index)
                let bigram = String(currentCJKScalars[index]) + String(currentCJKScalars[nextIndex])
                tokens.append(RelevanceToken(kind: .cjkBigram, value: bigram))
            }
        }

        for scalar in text.lowercased().unicodeScalars {
            if isCJKIdeograph(scalar) {
                appendCurrentWord()
                if droppingPromptStopWords,
                   promptStopCharacters.contains(scalar) {
                    appendCurrentCJKRun()
                } else {
                    currentCJKScalars.append(scalar)
                }
            } else if CharacterSet.alphanumerics.contains(scalar) {
                appendCurrentCJKRun()
                currentWord.append(contentsOf: String(scalar))
            } else {
                appendCurrentWord()
                appendCurrentCJKRun()
            }
        }

        appendCurrentWord()
        appendCurrentCJKRun()
        return tokens
    }

    private static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x2CEB0...0x2EBEF,
             0x30000...0x3134F:
            return true
        default:
            return false
        }
    }
}

protocol MemoryRetriever {
    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord]
}

protocol MemoryWriter {
    func extractMemories(from session: ChatSession, messages: [ChatMessage]) async throws -> [MemoryCandidate]
}

struct EmptyMemoryRetriever: MemoryRetriever {
    func retrieveRelevantMemories(for _: ChatContext) async throws -> [MemoryRecord] {
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
            matching: settings.filter,
            referenceDate: Date()
        )
        let sortedMemories = Self.sortedForPresentation(eligibleMemories)

        switch settings.filter {
        case .smart:
            let matchedMemories = MemoryTextSearch.rankedByRelevance(
                sortedMemories,
                matching: Self.retrievalQuery(from: context)
            )
            return Self.limited(matchedMemories, maximumMemories: settings.maximumMemories)
        case .all, .last24Hours, .last7Days, .last30Days, .last90Days, .lastYear:
            return Self.limited(sortedMemories, maximumMemories: settings.maximumMemories)
        }
    }

    private static func retrievalQuery(from context: ChatContext) -> String {
        context.messages.last(where: { $0.role == .user })?.content ?? ""
    }

    private static func memories(
        _ memories: [MemoryRecord],
        matching filter: MemoryInjectionFilter,
        referenceDate: Date
    ) -> [MemoryRecord] {
        guard let timeInterval = filter.timeInterval else {
            return memories
        }

        let cutoffDate = referenceDate.addingTimeInterval(-timeInterval)
        return memories.filter {
            $0.updatedAt >= cutoffDate
        }
    }

    private static func limited(_ memories: [MemoryRecord], maximumMemories: Int?) -> [MemoryRecord] {
        guard let maximumMemories else {
            return memories
        }

        return Array(memories.prefix(maximumMemories))
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
            return String(localized: .memoriesErrorStorageUnavailable)
        }
    }
}

final class MemoryManager {
    private let store: (any MemoryStore)?
    private let settingsStore: any MemorySettingsStore
    private let retriever: any MemoryRetriever
    private let writer: any MemoryWriter

    init(
        store: (any MemoryStore)? = nil,
        settingsStore: any MemorySettingsStore = UserDefaultsMemorySettingsStore.shared,
        retriever: (any MemoryRetriever)? = nil,
        writer: any MemoryWriter = EmptyMemoryWriter()
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
    }

    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        try await retriever.retrieveRelevantMemories(for: context)
    }

    func extractCandidates(from session: ChatSession, messages: [ChatMessage]) async throws -> [MemoryCandidate] {
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
        let matches = MemoryTextSearch.filtered(memories, matching: query)

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

}
