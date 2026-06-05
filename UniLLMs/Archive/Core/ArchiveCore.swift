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
        archivedAt: Date
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
        case let .userMessageWithAttachments(text, attachments):
            let attachmentText = attachments
                .map { [$0.filename, $0.contentType].joined(separator: " ") }
                .joined(separator: " ")
            return [text, attachmentText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case let .assistantContent(markdown):
            return markdown
        case let .assistantToolCalls(toolCalls):
            return toolCalls
                .map { [$0.toolID, $0.presentationName, $0.serializedArguments].joined(separator: " ") }
                .joined(separator: " ")
        case let .toolEvent(event):
            return event.searchableText
        case let .messageRevision(revision):
            return revision.events
                .map(\.searchableText)
                .joined(separator: " ")
        }
    }
}

nonisolated private extension ChatTimelineRevisionEvent {
    var searchableText: String {
        switch kind {
        case let .userMessage(text),
             let .assistantReasoning(text):
            return text
        case let .userMessageWithAttachments(text, attachments):
            let attachmentText = attachments
                .map { [$0.filename, $0.contentType].joined(separator: " ") }
                .joined(separator: " ")
            return [text, attachmentText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case let .assistantContent(markdown):
            return markdown
        case let .assistantToolCalls(toolCalls):
            return toolCalls
                .map { [$0.toolID, $0.presentationName, $0.serializedArguments].joined(separator: " ") }
                .joined(separator: " ")
        case let .toolEvent(event):
            return event.searchableText
        }
    }
}

nonisolated private extension ChatToolEvent {
    var searchableText: String {
        switch self {
        case let .started(toolCall):
            return [toolCall.toolID, toolCall.presentationName, toolCall.serializedArguments].joined(separator: " ")
        case let .completed(toolCall, result):
            return [toolCall.toolID, toolCall.presentationName, result].joined(separator: " ")
        case let .failed(toolCall, message):
            return [toolCall.toolID, toolCall.presentationName, message].joined(separator: " ")
        }
    }
}
