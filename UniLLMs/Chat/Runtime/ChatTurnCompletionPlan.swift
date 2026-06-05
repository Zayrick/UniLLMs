//
//  ChatTurnCompletionPlan.swift
//  UniLLMs
//
//  Applies the timeline and session metadata changes for a completed chat turn.
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated struct ChatTurnCompletionPlan: Equatable {
    nonisolated struct Result: Equatable {
        var timeline: [ChatTimelineEvent]
        var sessionUpdatedAt: Date
    }

    var turnID: UUID
    var activeTurnID: UUID?
    var userEventID: UUID
    var progressEvents: [ChatTimelineEvent]
    var shouldKeepUserMessage: Bool

    func apply(
        to timeline: [ChatTimelineEvent],
        sessionUpdatedAt: Date
    ) -> Result? {
        guard activeTurnID == turnID else {
            return nil
        }

        var updatedTimeline = timeline
        var updatedSessionTimestamp = sessionUpdatedAt
        if !progressEvents.isEmpty {
            updatedTimeline.append(contentsOf: progressEvents)
            if let latestProgressTimestamp = progressEvents.map(\.timestamp).max(),
               latestProgressTimestamp > updatedSessionTimestamp {
                updatedSessionTimestamp = latestProgressTimestamp
            }
        } else if !shouldKeepUserMessage {
            updatedTimeline.removeAll { $0.id == userEventID }
        }

        return Result(
            timeline: updatedTimeline,
            sessionUpdatedAt: updatedSessionTimestamp
        )
    }
}
