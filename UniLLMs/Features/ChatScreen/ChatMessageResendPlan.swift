//
//  ChatMessageResendPlan.swift
//  UniLLMs
//
//  Prepares replacement-message resend state without tying the decision to UIKit.
//

import Foundation

struct ChatMessageResendPlan: Equatable {
    enum Decision: Equatable {
        case resend(ChatMessageResendPlan)
        case ignore
        case fail(ChatMessageActionPolicy.FailureReason)
    }

    var messageID: UUID
    var text: String
    var attachments: [ChatAttachment]
    var firstRemovedIndex: Int
    var presentationState: ChatResponsePresentationState

    static func make(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment],
        firstRemovedIndex: Int?,
        isResponseActive: Bool
    ) -> Decision {
        let removedIndex: Int
        switch ChatMessageActionPolicy.resendDecision(
            isResponseActive: isResponseActive,
            text: text,
            hasAttachments: !attachments.isEmpty,
            containsMessage: firstRemovedIndex != nil
        ) {
        case .resend:
            guard let firstRemovedIndex else {
                return .fail(.messageUnavailable)
            }
            removedIndex = firstRemovedIndex
        case .ignore:
            return .ignore
        case let .fail(reason):
            return .fail(reason)
        }

        return .resend(
            ChatMessageResendPlan(
                messageID: messageID,
                text: text,
                attachments: attachments,
                firstRemovedIndex: removedIndex,
                presentationState: .replacementMessage(
                    prompt: text,
                    attachments: attachments
                )
            )
        )
    }
}
