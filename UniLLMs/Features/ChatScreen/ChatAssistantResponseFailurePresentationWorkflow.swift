//
//  ChatAssistantResponseFailurePresentationWorkflow.swift
//  UniLLMs
//
//  Owns assistant response failure presentation and draft recovery.
//

import UIKit

@MainActor
final class ChatAssistantResponseFailurePresentationWorkflow {
    typealias ActiveContext = ChatActiveAssistantResponseContext<
        SentMessageBubbleView,
        AssistantResponseTextView
    >

    struct Result: Equatable {
        var shouldClearActiveResponseView: Bool
    }

    private let cancelMessageAttachmentDisplays: (UUID) -> Void
    private let removeViews: ([UIView]) -> Void
    private let restoreComposerDraft: (String, [ChatAttachment]) -> Void
    private let presentError: (String) -> Void
    private let setResponseError: (String, AssistantResponseTextView) -> Void
    private let invalidateRemovedViewsLayout: () -> Void
    private let reconcileAfterRemovedViews: () -> Void

    init(
        cancelMessageAttachmentDisplays: @escaping (UUID) -> Void,
        removeViews: @escaping ([UIView]) -> Void,
        restoreComposerDraft: @escaping (String, [ChatAttachment]) -> Void,
        presentError: @escaping (String) -> Void,
        setResponseError: @escaping (String, AssistantResponseTextView) -> Void,
        invalidateRemovedViewsLayout: @escaping () -> Void,
        reconcileAfterRemovedViews: @escaping () -> Void
    ) {
        self.cancelMessageAttachmentDisplays = cancelMessageAttachmentDisplays
        self.removeViews = removeViews
        self.restoreComposerDraft = restoreComposerDraft
        self.presentError = presentError
        self.setResponseError = setResponseError
        self.invalidateRemovedViewsLayout = invalidateRemovedViewsLayout
        self.reconcileAfterRemovedViews = reconcileAfterRemovedViews
    }

    func presentFailure(
        message: String,
        responseView: AssistantResponseTextView,
        context: ActiveContext?,
        activeResponseView: AssistantResponseTextView?
    ) -> Result {
        guard let context,
              let recoveryPlan = context.failureRecoveryPlan(for: responseView) else {
            setResponseError(message, responseView)
            return Result(shouldClearActiveResponseView: false)
        }

        removeFailedResponseViews(context)
        restoreComposerDraft(recoveryPlan.prompt, recoveryPlan.attachments)
        presentError(message)
        return Result(
            shouldClearActiveResponseView: context.contains(responseView: activeResponseView)
        )
    }

    private func removeFailedResponseViews(_ context: ActiveContext) {
        if let sentMessageID = context.sentMessageID {
            cancelMessageAttachmentDisplays(sentMessageID)
        }
        removeViews(context.removableViews)
        invalidateRemovedViewsLayout()
        reconcileAfterRemovedViews()
    }
}
