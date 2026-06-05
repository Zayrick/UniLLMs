//
//  ChatRevisionSwitchPlan.swift
//  UniLLMs
//
//  Applies the timeline changes for restoring an archived message revision.
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated struct ChatRevisionSwitchPlan: Equatable {
    nonisolated struct Result: Equatable {
        var timeline: [ChatTimelineEvent]
        var sessionUpdatedAt: Date
    }

    var anchorUserMessageID: UUID
    var revisionID: UUID
    var switchedAt: Date

    func apply(to timeline: [ChatTimelineEvent]) -> Result? {
        guard let selectedRevision = ChatTimelineEvent
            .messageRevisions(from: timeline)[anchorUserMessageID]?
            .first(where: { $0.id == revisionID }),
              let archivedBranch = ChatTimelineBranchArchive.make(
                from: timeline,
                anchoredAt: anchorUserMessageID,
                excludingRevisionID: revisionID
              ) else {
            return nil
        }

        let currentRevision = ChatMessageRevision(
            anchorUserMessageID: anchorUserMessageID,
            archivedAt: switchedAt,
            events: archivedBranch.currentBranchEvents
        )
        var updatedTimeline = archivedBranch.prefixMainlineEvents + archivedBranch.retainedRevisionEvents
        if !currentRevision.events.isEmpty {
            updatedTimeline.append(
                ChatTimelineEvent(
                    timestamp: switchedAt,
                    kind: .messageRevision(currentRevision)
                )
            )
        }
        updatedTimeline.append(contentsOf: selectedRevision.events.map(\.timelineEvent))

        return Result(
            timeline: updatedTimeline,
            sessionUpdatedAt: switchedAt
        )
    }
}
