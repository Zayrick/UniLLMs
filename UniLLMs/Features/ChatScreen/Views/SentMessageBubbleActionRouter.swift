//
//  SentMessageBubbleActionRouter.swift
//  UniLLMs
//
//  Routes sent-message menu actions to side effects with context-menu dismissal ordering.
//

import Foundation

@MainActor
struct SentMessageBubbleActionRouter {
    var messageText: String
    var attachments: [ChatAttachment]
    var copyText: (String) -> Void
    var performAfterDismissal: (@escaping () -> Void) -> Void
    var resend: (_ text: String, _ attachments: [ChatAttachment]) -> Void
    var editAndResend: (_ text: String, _ attachments: [ChatAttachment]) -> Void
    var showHistory: () -> Void

    func perform(_ action: SentMessageBubbleAction) {
        switch action {
        case .copy:
            copyText(messageText)
        case .resend:
            performAfterDismissal {
                resend(messageText, attachments)
            }
        case .editAndResend:
            performAfterDismissal {
                editAndResend(messageText, attachments)
            }
        case .showHistory:
            performAfterDismissal {
                showHistory()
            }
        }
    }
}
