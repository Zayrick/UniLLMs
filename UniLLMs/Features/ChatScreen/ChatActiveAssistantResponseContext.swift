//
//  ChatActiveAssistantResponseContext.swift
//  UniLLMs
//
//  Tracks active assistant response presentation lifecycle state.
//

import UIKit

nonisolated struct ChatAssistantResponseFailureRecoveryPlan: Equatable {
    var prompt: String
    var attachments: [ChatAttachment]
}

@MainActor
final class ChatActiveAssistantResponseContext<SentMessageView: AnyObject, ResponseView: AnyObject> {
    private var presentationState: ChatResponsePresentationState
    let sentMessageID: UUID?
    private weak var sentMessageView: SentMessageView?
    private weak var responseView: ResponseView?

    init(
        presentationState: ChatResponsePresentationState,
        sentMessageID: UUID? = nil,
        sentMessageView: SentMessageView,
        responseView: ResponseView
    ) {
        self.presentationState = presentationState
        self.sentMessageID = sentMessageID
        self.sentMessageView = sentMessageView
        self.responseView = responseView
    }

    func contains(responseView candidate: ResponseView?) -> Bool {
        guard let candidate else {
            return false
        }

        return responseView === candidate
    }

    func recordVisibleProgress(from delta: ChatResponseDelta) {
        presentationState.recordVisibleProgress(from: delta)
    }

    func failureRecoveryPlan(for candidate: ResponseView) -> ChatAssistantResponseFailureRecoveryPlan? {
        guard contains(responseView: candidate),
              presentationState.shouldRestoreDraftAfterFailure else {
            return nil
        }

        return ChatAssistantResponseFailureRecoveryPlan(
            prompt: presentationState.prompt,
            attachments: presentationState.attachments
        )
    }
}

extension ChatActiveAssistantResponseContext where SentMessageView: UIView, ResponseView: UIView {
    var removableViews: [UIView] {
        var views: [UIView] = []
        if let sentMessageView {
            views.append(sentMessageView)
        }
        if let responseView {
            views.append(responseView)
        }
        return views
    }
}
