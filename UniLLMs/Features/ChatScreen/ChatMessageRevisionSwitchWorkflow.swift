//
//  ChatMessageRevisionSwitchWorkflow.swift
//  UniLLMs
//
//  Owns switching to an archived message revision and refreshing chat presentation.
//

import Foundation

@MainActor
struct ChatMessageRevisionSwitchWorkflow {
    var isResponseActive: () -> Bool
    var switchToMessageRevision: (_ messageID: UUID, _ revisionID: UUID) throws -> [ChatTimelineEvent]
    var renderConversationTimeline: ([ChatTimelineEvent]) -> Void
    var lockMessagesToBottom: () -> Void
    var updateHeader: () -> Void
    var reloadHistorySessions: (_ selectedSessionID: UUID?) -> Void
    var currentSessionID: () -> UUID
    var presentActionFailure: (ChatMessageActionPolicy.FailureReason) -> Void
    var presentError: (String) -> Void

    func switchRevision(
        messageID: UUID,
        revisionID: UUID
    ) {
        switch ChatMessageActionPolicy.revisionSwitchDecision(
            isResponseActive: isResponseActive()
        ) {
        case .switchRevision:
            break
        case let .fail(reason):
            presentActionFailure(reason)
            return
        }

        do {
            let events = try switchToMessageRevision(messageID, revisionID)
            renderConversationTimeline(events)
            lockMessagesToBottom()
            updateHeader()
            reloadHistorySessions(currentSessionID())
        } catch {
            presentError(error.localizedDescription)
        }
    }
}
