//
//  ChatOutgoingMessageTransactionPlan.swift
//  UniLLMs
//
//  Describes how an outgoing user message should enter the chat screen transaction.
//

import CoreGraphics
import Foundation

struct ChatOutgoingMessageTransactionPlan: Equatable {
    enum LoadingPresentation: Equatable {
        case afterSendAnimation
        case immediately
    }

    var messageID: UUID
    var prompt: String
    var attachments: [ChatAttachment]
    var replacingUserMessageID: UUID?
    var firstRemovedIndex: Int?
    var initialBubbleAlpha: CGFloat
    var presentationState: ChatResponsePresentationState
    var consumesComposerAttachments: Bool
    var refreshesEditHistory: Bool
    var loadingPresentation: LoadingPresentation

    static func newMessage(
        text: String,
        attachments: [ChatAttachment],
        messageID: UUID = UUID()
    ) -> ChatOutgoingMessageTransactionPlan {
        ChatOutgoingMessageTransactionPlan(
            messageID: messageID,
            prompt: text,
            attachments: attachments,
            replacingUserMessageID: nil,
            firstRemovedIndex: nil,
            initialBubbleAlpha: 0.0,
            presentationState: .newMessage(
                prompt: text,
                attachments: attachments
            ),
            consumesComposerAttachments: true,
            refreshesEditHistory: false,
            loadingPresentation: .afterSendAnimation
        )
    }

    static func replacement(
        resendPlan: ChatMessageResendPlan
    ) -> ChatOutgoingMessageTransactionPlan {
        ChatOutgoingMessageTransactionPlan(
            messageID: resendPlan.messageID,
            prompt: resendPlan.text,
            attachments: resendPlan.attachments,
            replacingUserMessageID: resendPlan.messageID,
            firstRemovedIndex: resendPlan.firstRemovedIndex,
            initialBubbleAlpha: 1.0,
            presentationState: resendPlan.presentationState,
            consumesComposerAttachments: false,
            refreshesEditHistory: true,
            loadingPresentation: .immediately
        )
    }
}
