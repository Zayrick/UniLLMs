//
//  ChatMessageResendWorkflow.swift
//  UniLLMs
//
//  Owns resending an existing user message as a replacement turn.
//

import Foundation

enum ChatMessageResendWorkflowFailure: LocalizedError, Equatable {
    case unavailable

    var errorDescription: String? {
        String(localized: .runtimeErrorMessageCouldNotBeEdited)
    }
}

@MainActor
struct ChatMessageResendWorkflow {
    var isResponseActive: () -> Bool
    var firstRemovedIndex: (_ messageID: UUID) -> Int?
    var layoutIfNeeded: () -> Void
    var captureExistingMessagesSnapshot: () -> ChatExistingMessagesShiftAnimator.Snapshot
    var prepareOutgoingTurn: (ChatOutgoingMessageTransactionPlan) throws -> ChatPreparedOutgoingTurn
    var performTransaction: (
        _ transactionPlan: ChatOutgoingMessageTransactionPlan,
        _ preparedStream: ChatPreparedAssistantResponseStream,
        _ existingMessagesSnapshot: ChatExistingMessagesShiftAnimator.Snapshot
    ) -> Void
    var presentActionFailure: (ChatMessageActionPolicy.FailureReason) -> Void
    var presentError: (String) -> Void

    func resendEditedMessage(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        resendMessage(
            messageID: messageID,
            text: ChatMessageActionPolicy.editedMessageText(text),
            attachments: attachments
        )
    }

    func resendMessage(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        guard !isResponseActive() else {
            presentActionFailure(.responseInProgress)
            return
        }

        let decision = ChatMessageResendPlan.make(
            messageID: messageID,
            text: text,
            attachments: attachments,
            firstRemovedIndex: firstRemovedIndex(messageID),
            isResponseActive: false
        )

        let resendPlan: ChatMessageResendPlan
        switch decision {
        case let .resend(plan):
            resendPlan = plan
        case .ignore:
            return
        case let .fail(reason):
            presentActionFailure(reason)
            return
        }

        layoutIfNeeded()
        let existingMessagesSnapshot = captureExistingMessagesSnapshot()
        let transactionPlan = ChatOutgoingMessageTransactionPlan.replacement(resendPlan: resendPlan)

        do {
            let preparedTurn = try prepareOutgoingTurn(transactionPlan)
            performTransaction(
                preparedTurn.transactionPlan,
                preparedTurn.preparedStream,
                existingMessagesSnapshot
            )
        } catch {
            presentError(error.localizedDescription)
        }
    }
}
