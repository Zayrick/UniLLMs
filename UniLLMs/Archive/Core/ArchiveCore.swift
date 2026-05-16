//
//  ArchiveCore.swift
//  UniLLMs
//
//  Defines conversation archive, import/export, and archive store protocols; currently a lightweight protocol boundary for future archive features.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct ConversationArchive: Codable, Equatable, Identifiable {
    var id: UUID
    var session: ChatSession
    var events: [ChatTimelineEvent]
    var archivedAt: Date

    init(
        id: UUID = UUID(),
        session: ChatSession,
        events: [ChatTimelineEvent],
        archivedAt: Date = Date()
    ) {
        self.id = id
        self.session = session
        self.events = events
        self.archivedAt = archivedAt
    }
}

nonisolated struct ArchiveFilter: Codable, Equatable {
    var query: String
}

protocol ArchiveExporter {
    func export(_ archive: ConversationArchive) throws -> Data
}

protocol ArchiveImporter {
    func importArchive(from data: Data) throws -> ConversationArchive
}

protocol ArchiveStore {
    func save(_ archive: ConversationArchive) async throws
    func fetchArchives(matching filter: ArchiveFilter?) async throws -> [ConversationArchive]
}

final class InMemoryArchiveStore: ArchiveStore {
    private var archives: [ConversationArchive] = []

    func save(_ archive: ConversationArchive) async throws {
        if let index = archives.firstIndex(where: { $0.id == archive.id }) {
            archives[index] = archive
        } else {
            archives.append(archive)
        }
    }

    func fetchArchives(matching filter: ArchiveFilter?) async throws -> [ConversationArchive] {
        guard let query = filter?.query.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return archives
        }

        return archives.filter { archive in
            archive.session.title.localizedCaseInsensitiveContains(query)
                || archive.events.contains {
                    $0.searchableText.localizedCaseInsensitiveContains(query)
                }
        }
    }
}

nonisolated private extension ChatTimelineEvent {
    var searchableText: String {
        switch kind {
        case let .userMessage(text),
             let .assistantReasoning(text):
            return text
        case let .assistantContent(markdown):
            return markdown
        case let .toolCallStarted(_, toolID, displayName, arguments):
            return [toolID, displayName, arguments].joined(separator: " ")
        case let .toolCallCompleted(_, toolID, displayName, result):
            return [toolID, displayName, result].joined(separator: " ")
        case let .toolCallFailed(_, toolID, displayName, message):
            return [toolID, displayName, message].joined(separator: " ")
        }
    }
}
