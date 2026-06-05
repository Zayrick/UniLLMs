//
//  ChatHistoryActionPolicy.swift
//  UniLLMs
//
//  Decides which history actions are valid while the chat screen is streaming.
//

import Foundation

struct ChatHistoryActionPolicy: Equatable {
    enum SelectionDecision: Equatable {
        case load
        case ignore
    }

    enum DeletionDecision: Equatable {
        case deleteOnly
        case deleteAndResetCurrent
        case ignore
    }

    static func selectionDecision(isResponseActive: Bool) -> SelectionDecision {
        isResponseActive ? .ignore : .load
    }

    static func deletionDecision(
        sessionID: UUID,
        currentSessionID: UUID,
        isResponseActive: Bool
    ) -> DeletionDecision {
        let isCurrentSession = sessionID == currentSessionID
        if isResponseActive && isCurrentSession {
            return .ignore
        }

        return isCurrentSession ? .deleteAndResetCurrent : .deleteOnly
    }

    static func deletionCompletionDecision(
        sessionID: UUID,
        currentSessionID: UUID,
        isResponseActive: Bool
    ) -> DeletionDecision {
        deletionDecision(
            sessionID: sessionID,
            currentSessionID: currentSessionID,
            isResponseActive: isResponseActive
        )
    }
}
