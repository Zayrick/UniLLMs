//
//  ChatTimelineBranchArchive.swift
//  UniLLMs
//
//  Splits a chat timeline when the current branch is archived as a revision.
//

import Foundation

nonisolated struct ChatTimelineBranchArchive: Equatable {
    var prefixMainlineEvents: [ChatTimelineEvent]
    var currentBranchEvents: [ChatTimelineEvent]
    var retainedRevisionEvents: [ChatTimelineEvent]

    static func make(
        from timeline: [ChatTimelineEvent],
        anchoredAt anchorUserMessageID: UUID,
        excludingRevisionID: UUID? = nil
    ) -> ChatTimelineBranchArchive? {
        let mainlineEvents = timeline.filter { event in
            if case .messageRevision = event.kind {
                return false
            }

            return true
        }
        guard let anchorIndex = mainlineEvents.firstIndex(where: { event in
            event.id == anchorUserMessageID && event.isUserMessage
        }) else {
            return nil
        }

        let retainedRevisionEvents = timeline.filter { event in
            guard case let .messageRevision(revision) = event.kind else {
                return false
            }

            return revision.id != excludingRevisionID
        }

        return ChatTimelineBranchArchive(
            prefixMainlineEvents: Array(mainlineEvents[..<anchorIndex]),
            currentBranchEvents: Array(mainlineEvents[anchorIndex...]),
            retainedRevisionEvents: retainedRevisionEvents
        )
    }
}
