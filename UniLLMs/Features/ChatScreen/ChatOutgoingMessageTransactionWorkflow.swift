//
//  ChatOutgoingMessageTransactionWorkflow.swift
//  UniLLMs
//
//  Performs the ordered UI work for an outgoing user-message transaction.
//  Created by Codex on 2026/6/5.
//

import UIKit

@MainActor
protocol ChatOutgoingMessageTransactionMessageAdapting: AnyObject {
    func removeReplacementMessages(startingAt firstRemovedIndex: Int)
    func appendOutgoingMessage(
        for transactionPlan: ChatOutgoingMessageTransactionPlan
    ) -> ChatMessageStackAdapter.OutgoingMessageViews
    func loadAttachmentDisplays(for transactionPlan: ChatOutgoingMessageTransactionPlan)
    func refreshEditHistory(for bubbleView: SentMessageBubbleView, messageID: UUID)
}

@MainActor
protocol ChatOutgoingMessageTransactionScreenAdapting: AnyObject {
    func layoutIfNeeded()
    func scrollToBottom()
    func animateExistingMessages(from snapshot: ChatExistingMessagesShiftAnimator.Snapshot)
    func presentAssistantLoading(
        presentation: ChatOutgoingMessageTransactionPlan.LoadingPresentation,
        outgoingViews: ChatMessageStackAdapter.OutgoingMessageViews,
        sendTransition: ChatComposerSendTransition?,
        attachments: [ChatAttachment]
    )
}

@MainActor
protocol ChatOutgoingMessageTransactionResponseActivating: AnyObject {
    func activateAssistantResponseStream(
        _ preparedStream: ChatPreparedAssistantResponseStream,
        sentMessageID: UUID,
        outgoingViews: ChatMessageStackAdapter.OutgoingMessageViews,
        presentationState: ChatResponsePresentationState
    )
}

@MainActor
final class ChatOutgoingMessageTransactionWorkflow {
    private let messages: any ChatOutgoingMessageTransactionMessageAdapting
    private let screen: any ChatOutgoingMessageTransactionScreenAdapting
    private let responseActivator: any ChatOutgoingMessageTransactionResponseActivating

    init(
        messages: any ChatOutgoingMessageTransactionMessageAdapting,
        screen: any ChatOutgoingMessageTransactionScreenAdapting,
        responseActivator: any ChatOutgoingMessageTransactionResponseActivating
    ) {
        self.messages = messages
        self.screen = screen
        self.responseActivator = responseActivator
    }

    func perform(
        _ transactionPlan: ChatOutgoingMessageTransactionPlan,
        preparedStream: ChatPreparedAssistantResponseStream,
        existingMessagesSnapshot: ChatExistingMessagesShiftAnimator.Snapshot,
        sendTransition: ChatComposerSendTransition?
    ) {
        if let firstRemovedIndex = transactionPlan.firstRemovedIndex {
            messages.removeReplacementMessages(startingAt: firstRemovedIndex)
        }

        let outgoingViews = messages.appendOutgoingMessage(for: transactionPlan)
        messages.loadAttachmentDisplays(for: transactionPlan)

        screen.layoutIfNeeded()
        screen.scrollToBottom()
        screen.layoutIfNeeded()

        responseActivator.activateAssistantResponseStream(
            preparedStream,
            sentMessageID: transactionPlan.messageID,
            outgoingViews: outgoingViews,
            presentationState: transactionPlan.presentationState
        )
        if transactionPlan.refreshesEditHistory {
            messages.refreshEditHistory(
                for: outgoingViews.bubbleView,
                messageID: transactionPlan.messageID
            )
        }
        screen.animateExistingMessages(from: existingMessagesSnapshot)
        screen.presentAssistantLoading(
            presentation: transactionPlan.loadingPresentation,
            outgoingViews: outgoingViews,
            sendTransition: sendTransition,
            attachments: transactionPlan.attachments
        )
    }
}

@MainActor
final class ChatOutgoingMessageTransactionMessageAdapter: ChatOutgoingMessageTransactionMessageAdapting {
    typealias EditHistoryCountProvider = @MainActor (UUID) -> Int

    private let messageStackAdapter: ChatMessageStackAdapter
    private let attachmentDisplayUpdater: ChatMessageAttachmentDisplayUpdater
    private let editHistoryCount: EditHistoryCountProvider

    init(
        messageStackAdapter: ChatMessageStackAdapter,
        attachmentDisplayUpdater: ChatMessageAttachmentDisplayUpdater,
        editHistoryCount: @escaping EditHistoryCountProvider
    ) {
        self.messageStackAdapter = messageStackAdapter
        self.attachmentDisplayUpdater = attachmentDisplayUpdater
        self.editHistoryCount = editHistoryCount
    }

    func removeReplacementMessages(startingAt firstRemovedIndex: Int) {
        attachmentDisplayUpdater.cancelMessageLoads()
        messageStackAdapter.removeMessagesStarting(at: firstRemovedIndex)
    }

    func appendOutgoingMessage(
        for transactionPlan: ChatOutgoingMessageTransactionPlan
    ) -> ChatMessageStackAdapter.OutgoingMessageViews {
        messageStackAdapter.appendOutgoingMessage(
            messageID: transactionPlan.messageID,
            text: transactionPlan.prompt,
            attachments: transactionPlan.attachments,
            initialBubbleAlpha: transactionPlan.initialBubbleAlpha
        )
    }

    func loadAttachmentDisplays(for transactionPlan: ChatOutgoingMessageTransactionPlan) {
        attachmentDisplayUpdater.loadDisplays(
            messageID: transactionPlan.messageID,
            attachments: transactionPlan.attachments
        )
    }

    func refreshEditHistory(for bubbleView: SentMessageBubbleView, messageID: UUID) {
        bubbleView.editHistoryCount = editHistoryCount(messageID)
    }
}

@MainActor
final class ChatOutgoingMessageTransactionScreenAdapter: ChatOutgoingMessageTransactionScreenAdapting {
    typealias ScrollToBottom = @MainActor () -> Void
    typealias LoadingPresenter = @MainActor (AssistantResponseTextView) -> Void

    private weak var layoutView: UIView?
    private let existingMessagesShiftAnimator: ChatExistingMessagesShiftAnimator
    private let sentMessageSendAnimator: any ChatSentMessageSendAnimating
    private let scrollToBottomHandler: ScrollToBottom
    private let presentLoading: LoadingPresenter

    init(
        layoutView: UIView,
        existingMessagesShiftAnimator: ChatExistingMessagesShiftAnimator,
        sentMessageSendAnimator: any ChatSentMessageSendAnimating,
        scrollToBottom: @escaping ScrollToBottom,
        presentLoading: @escaping LoadingPresenter
    ) {
        self.layoutView = layoutView
        self.existingMessagesShiftAnimator = existingMessagesShiftAnimator
        self.sentMessageSendAnimator = sentMessageSendAnimator
        self.scrollToBottomHandler = scrollToBottom
        self.presentLoading = presentLoading
    }

    func layoutIfNeeded() {
        layoutView?.layoutIfNeeded()
    }

    func scrollToBottom() {
        scrollToBottomHandler()
    }

    func animateExistingMessages(from snapshot: ChatExistingMessagesShiftAnimator.Snapshot) {
        existingMessagesShiftAnimator.animateChanges(from: snapshot)
    }

    func presentAssistantLoading(
        presentation: ChatOutgoingMessageTransactionPlan.LoadingPresentation,
        outgoingViews: ChatMessageStackAdapter.OutgoingMessageViews,
        sendTransition: ChatComposerSendTransition?,
        attachments: [ChatAttachment]
    ) {
        switch presentation {
        case .afterSendAnimation:
            guard let sendTransition else {
                showAssistantLoadingIfNeeded(in: outgoingViews.responseView)
                return
            }

            animateSentMessage(
                bubbleView: outgoingViews.bubbleView,
                transition: sendTransition,
                attachments: attachments
            ) { [weak self, weak responseView = outgoingViews.responseView] in
                guard let self,
                      let responseView else {
                    return
                }

                self.showAssistantLoadingIfNeeded(in: responseView)
            }
        case .immediately:
            showAssistantLoadingIfNeeded(in: outgoingViews.responseView)
        }
    }

    private func animateSentMessage(
        bubbleView: SentMessageBubbleView,
        transition: ChatComposerSendTransition,
        attachments: [ChatAttachment],
        completion: @escaping () -> Void
    ) {
        sentMessageSendAnimator.animate(
            bubbleView: bubbleView,
            transition: transition,
            attachments: attachments,
            completion: completion
        )
    }

    private func showAssistantLoadingIfNeeded(in responseView: AssistantResponseTextView) {
        presentLoading(responseView)
    }
}

@MainActor
final class ChatOutgoingMessageTransactionResponseActivationAdapter:
    ChatOutgoingMessageTransactionResponseActivating {
    typealias ActiveResponseContext = ChatActiveAssistantResponseContext<
        SentMessageBubbleView,
        AssistantResponseTextView
    >
    typealias Activator = @MainActor (
        AsyncThrowingStream<ChatResponseDelta, Error>,
        AssistantResponseTextView,
        ChatContinuationTask?,
        ActiveResponseContext
    ) -> Void

    private let activate: Activator

    init(activate: @escaping Activator) {
        self.activate = activate
    }

    func activateAssistantResponseStream(
        _ preparedStream: ChatPreparedAssistantResponseStream,
        sentMessageID: UUID,
        outgoingViews: ChatMessageStackAdapter.OutgoingMessageViews,
        presentationState: ChatResponsePresentationState
    ) {
        activate(
            preparedStream.responseStream,
            outgoingViews.responseView,
            preparedStream.continuationTask,
            ActiveResponseContext(
                presentationState: presentationState,
                sentMessageID: sentMessageID,
                sentMessageView: outgoingViews.bubbleView,
                responseView: outgoingViews.responseView
            )
        )
    }
}
