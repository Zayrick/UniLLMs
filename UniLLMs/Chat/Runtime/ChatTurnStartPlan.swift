//
//  ChatTurnStartPlan.swift
//  UniLLMs
//
//  Applies the timeline and session metadata changes that start a user chat turn.
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated struct ChatTurnStartPlan: Equatable {
    nonisolated struct Result: Equatable {
        var session: ChatSession
        var timeline: [ChatTimelineEvent]
        var userEvent: ChatTimelineEvent
        var requestMessages: [ChatMessage]
    }

    var prompt: String
    var attachments: [ChatAttachment]
    var userMessageID: UUID
    var replacingUserMessageID: UUID?
    var sentAt: Date
    var emptyConversationTitle: String
    var attachmentFallbackTitle: String

    func apply(
        to session: ChatSession,
        timeline: [ChatTimelineEvent]
    ) -> Result? {
        var updatedSession = session
        var updatedTimeline = timeline

        if let replacingUserMessageID {
            guard let archivedBranch = ChatTimelineBranchArchive.make(
                from: updatedTimeline,
                anchoredAt: replacingUserMessageID
            ) else {
                return nil
            }

            let revision = ChatMessageRevision(
                anchorUserMessageID: replacingUserMessageID,
                archivedAt: sentAt,
                events: archivedBranch.currentBranchEvents
            )
            updatedTimeline = archivedBranch.prefixMainlineEvents + archivedBranch.retainedRevisionEvents
            if !revision.events.isEmpty {
                updatedTimeline.append(
                    ChatTimelineEvent(
                        timestamp: sentAt,
                        kind: .messageRevision(revision)
                    )
                )
            }
        }

        if ChatTimelineEvent.messages(from: updatedTimeline).isEmpty {
            updatedSession.title = ChatSessionTitle.make(
                prompt: prompt,
                attachments: attachments,
                emptyConversationTitle: emptyConversationTitle,
                attachmentFallbackTitle: attachmentFallbackTitle
            )
            if replacingUserMessageID == nil {
                updatedSession.createdAt = sentAt
            }
        }
        updatedSession.updatedAt = sentAt

        let userEvent = ChatTimelineEvent(
            id: userMessageID,
            timestamp: sentAt,
            kind: userEventKind
        )
        let requestTimeline = updatedTimeline + [userEvent]
        let requestMessages = ChatTimelineEvent.messages(from: requestTimeline)
        updatedTimeline.append(userEvent)

        return Result(
            session: updatedSession,
            timeline: updatedTimeline,
            userEvent: userEvent,
            requestMessages: requestMessages
        )
    }

    private var userEventKind: ChatTimelineEvent.Kind {
        attachments.isEmpty
            ? .userMessage(text: prompt)
            : .userMessageWithAttachments(text: prompt, attachments: attachments)
    }
}
