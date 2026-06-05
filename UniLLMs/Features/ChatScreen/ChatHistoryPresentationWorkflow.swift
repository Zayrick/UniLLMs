//
//  ChatHistoryPresentationWorkflow.swift
//  UniLLMs
//
//  Applies chat history load/delete completion effects.
//

import Foundation

@MainActor
struct ChatHistoryPresentationWorkflow {
    var isPrivacyModeEnabled: () -> Bool
    var clearPendingAttachments: (_ deleteFiles: Bool) -> Void
    var loadConversation: (ChatSession, [ChatTimelineEvent]) -> [ChatAttachment]
    var resetCurrentConversation: () -> Void
    var discardPrivateModeAttachments: ([ChatAttachment]) -> Void
    var renderConversationTimeline: ([ChatTimelineEvent]) -> Void
    var removeChatContent: () -> Void
    var reloadSelectedSystemPrompt: () -> Void
    var lockMessagesToBottom: () -> Void
    var updateHeader: () -> Void
    var confirmPendingSessionSelection: (UUID) -> Void
    var reloadHistorySessions: (UUID?) -> Void
    var closeSideMenu: () -> Void
    var currentSessionID: () -> UUID

    func presentLoadedSession(
        _ session: ChatSession,
        events: [ChatTimelineEvent]
    ) {
        if isPrivacyModeEnabled() {
            clearPendingAttachments(true)
        }

        let discardedAttachments = loadConversation(session, events)
        discardPrivateModeAttachments(discardedAttachments)
        renderConversationTimeline(events)
        reloadSelectedSystemPrompt()
        lockMessagesToBottom()
        updateHeader()
        confirmPendingSessionSelection(session.id)
        reloadHistorySessions(session.id)
        closeSideMenu()
    }

    func presentDeleteCompletion(
        _ completionDecision: ChatHistoryActionPolicy.DeletionDecision
    ) {
        switch completionDecision {
        case .deleteAndResetCurrent:
            resetCurrentConversation()
        case .deleteOnly,
             .ignore:
            reloadHistorySessions(currentSessionID())
        }
    }
}
