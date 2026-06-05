//
//  ChatSessionHistoryList.swift
//  UniLLMs
//
//  Builds the side-menu chat history sections from sessions and a search query.
//

import Foundation

nonisolated struct ChatSessionHistoryList {
    nonisolated struct Section: Equatable {
        var date: Date
        var sessions: [ChatSession]
    }

    nonisolated struct Position: Equatable {
        var section: Int
        var row: Int
    }

    var sections: [Section]

    init(
        sessions: [ChatSession] = [],
        query: String = "",
        calendar: Calendar = .current
    ) {
        self.init(
            sortedSessions: Self.sortedSessions(sessions),
            query: query,
            calendar: calendar
        )
    }

    init(
        sortedSessions: [ChatSession],
        query: String = "",
        calendar: Calendar = .current
    ) {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let filteredSessions = sortedSessions.filter { session in
            normalizedQuery.isEmpty || session.title.lowercased().contains(normalizedQuery)
        }
        let groupedSessions = Dictionary(grouping: filteredSessions) { session in
            calendar.startOfDay(for: session.updatedAt)
        }

        sections = groupedSessions.keys
            .sorted(by: >)
            .map { date in
                Section(
                    date: date,
                    sessions: Self.sortedSessions(groupedSessions[date] ?? [])
                )
            }
    }

    var isEmpty: Bool {
        sections.allSatisfy { $0.sessions.isEmpty }
    }

    func position(for sessionID: UUID) -> Position? {
        for (sectionIndex, section) in sections.enumerated() {
            if let rowIndex = section.sessions.firstIndex(where: { $0.id == sessionID }) {
                return Position(section: sectionIndex, row: rowIndex)
            }
        }

        return nil
    }

    static func sortedSessions(_ sessions: [ChatSession]) -> [ChatSession] {
        sessions.sorted(by: sortSessionsByLastSentDate)
    }

    private static func sortSessionsByLastSentDate(_ lhs: ChatSession, _ rhs: ChatSession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.createdAt > rhs.createdAt
    }
}
