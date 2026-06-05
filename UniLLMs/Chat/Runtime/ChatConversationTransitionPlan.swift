//
//  ChatConversationTransitionPlan.swift
//  UniLLMs
//
//  Applies conversation reset and load transitions while preserving private attachment cleanup.
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum ChatConversationTransitionPlan {
    nonisolated struct Result: Equatable {
        var session: ChatSession
        var timeline: [ChatTimelineEvent]
        var privacyModeEnabled: Bool
        var discardedPrivateAttachments: [ChatAttachment]
    }

    static func reset(
        currentTimeline: [ChatTimelineEvent],
        wasPrivacyModeEnabled: Bool,
        privacyMode: Bool,
        now: Date,
        emptyConversationTitle: String
    ) -> Result {
        Result(
            session: ChatSession(
                title: emptyConversationTitle,
                createdAt: now,
                updatedAt: now
            ),
            timeline: [],
            privacyModeEnabled: privacyMode,
            discardedPrivateAttachments: discardedPrivateAttachments(
                from: currentTimeline,
                wasPrivacyModeEnabled: wasPrivacyModeEnabled
            )
        )
    }

    static func load(
        session: ChatSession,
        events: [ChatTimelineEvent],
        currentTimeline: [ChatTimelineEvent],
        wasPrivacyModeEnabled: Bool
    ) -> Result {
        Result(
            session: session,
            timeline: ChatTimelineEvent.sortedChronologically(events),
            privacyModeEnabled: false,
            discardedPrivateAttachments: discardedPrivateAttachments(
                from: currentTimeline,
                wasPrivacyModeEnabled: wasPrivacyModeEnabled
            )
        )
    }

    private static func discardedPrivateAttachments(
        from currentTimeline: [ChatTimelineEvent],
        wasPrivacyModeEnabled: Bool
    ) -> [ChatAttachment] {
        wasPrivacyModeEnabled
            ? ChatTimelineEvent.attachments(from: currentTimeline)
            : []
    }
}
