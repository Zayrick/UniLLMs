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
    var messages: [ChatMessage]
    var archivedAt: Date

    init(
        id: UUID = UUID(),
        session: ChatSession,
        messages: [ChatMessage],
        archivedAt: Date = Date()
    ) {
        self.id = id
        self.session = session
        self.messages = messages
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
                || archive.messages.contains {
                    $0.content.localizedCaseInsensitiveContains(query)
                }
        }
    }
}
