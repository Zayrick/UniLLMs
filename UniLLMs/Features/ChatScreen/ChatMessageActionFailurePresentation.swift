//
//  ChatMessageActionFailurePresentation.swift
//  UniLLMs
//
//  Maps message action failures to user-facing alert text.
//

import Foundation

struct ChatMessageActionFailurePresentation: Equatable {
    enum MessageText: Equatable {
        case responseInProgress
        case messageUnavailable
    }

    var message: MessageText

    static func make(
        reason: ChatMessageActionPolicy.FailureReason
    ) -> ChatMessageActionFailurePresentation {
        switch reason {
        case .responseInProgress:
            return ChatMessageActionFailurePresentation(message: .responseInProgress)
        case .messageUnavailable:
            return ChatMessageActionFailurePresentation(message: .messageUnavailable)
        }
    }
}

extension ChatMessageActionFailurePresentation.MessageText {
    var localizedString: String {
        switch self {
        case .responseInProgress:
            return String(localized: .chatResponseInProgress)
        case .messageUnavailable:
            return String(localized: .chatMessageUnavailable)
        }
    }
}
