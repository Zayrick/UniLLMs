//
//  ChatComposerSendWorkflow.swift
//  UniLLMs
//
//  Owns the ordered composer-send preparation and outgoing transaction kickoff.
//

import Foundation

enum ChatComposerSendWorkflowFailure: LocalizedError, Equatable {
    case unavailable

    var errorDescription: String? {
        String(localized: .runtimeErrorMessageCouldNotBeSent)
    }
}

@MainActor
struct ChatComposerSendWorkflow {
    var isResponseActive: () -> Bool
    var layoutIfNeeded: () -> Void
    var captureExistingMessagesSnapshot: () -> ChatExistingMessagesShiftAnimator.Snapshot
    var prepareNewMessage: (_ text: String) throws -> ChatPreparedOutgoingTurn
    var performTransaction: (
        _ preparedTurn: ChatPreparedOutgoingTurn,
        _ existingMessagesSnapshot: ChatExistingMessagesShiftAnimator.Snapshot,
        _ sendTransition: ChatComposerSendTransition
    ) -> Void
    var presentError: (String) -> Void
    var updateHeaderAfterPrepareFailure: () -> Void

    @discardableResult
    func send(_ transition: ChatComposerSendTransition) -> Bool {
        guard !isResponseActive() else {
            presentError(String(localized: .chatResponseInProgress))
            return false
        }

        layoutIfNeeded()
        let existingMessagesSnapshot = captureExistingMessagesSnapshot()

        let preparedTurn: ChatPreparedOutgoingTurn
        do {
            preparedTurn = try prepareNewMessage(transition.text)
        } catch {
            presentError(error.localizedDescription)
            updateHeaderAfterPrepareFailure()
            return false
        }

        performTransaction(
            preparedTurn,
            existingMessagesSnapshot,
            transition
        )
        return true
    }
}
