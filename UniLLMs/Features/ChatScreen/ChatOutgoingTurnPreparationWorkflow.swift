//
//  ChatOutgoingTurnPreparationWorkflow.swift
//  UniLLMs
//
//  Prepares an outgoing chat turn before its UI transaction is performed.
//  Created by Codex on 2026/6/5.
//

import Foundation

struct ChatPreparedOutgoingTurn {
    var transactionPlan: ChatOutgoingMessageTransactionPlan
    var preparedStream: ChatPreparedAssistantResponseStream
}

@MainActor
protocol ChatAssistantResponseTurnStarting: AnyObject {
    func startTurn(
        prompt: String,
        attachments: [ChatAttachment],
        userMessageID: UUID,
        replacingUserMessageID: UUID?
    ) throws -> AsyncThrowingStream<ChatResponseDelta, Error>
}

@MainActor
protocol ChatAssistantResponseContinuationTaskBeginning: AnyObject {
    func beginResponseTask() throws -> ChatContinuationTask
}

@MainActor
protocol ChatAssistantResponseContinuationTaskPolicy: AnyObject {
    func beginResponseTaskIfNeeded() throws -> ChatContinuationTask?
}

@MainActor
protocol ChatOutgoingTurnComposerAttachmentStaging: AnyObject {
    var pendingAttachments: [ChatAttachment] { get }

    @discardableResult
    func consumePendingAttachments() -> [ChatAttachment]
}

@MainActor
final class ChatOutgoingTurnPreparationWorkflow {
    private let turnStarter: any ChatAssistantResponseTurnStarting
    private let continuationTaskPolicy: any ChatAssistantResponseContinuationTaskPolicy
    private let composerAttachmentStaging: any ChatOutgoingTurnComposerAttachmentStaging

    init(
        turnStarter: any ChatAssistantResponseTurnStarting,
        continuationTaskPolicy: any ChatAssistantResponseContinuationTaskPolicy,
        composerAttachmentStaging: any ChatOutgoingTurnComposerAttachmentStaging
    ) {
        self.turnStarter = turnStarter
        self.continuationTaskPolicy = continuationTaskPolicy
        self.composerAttachmentStaging = composerAttachmentStaging
    }

    func prepareNewMessage(
        text: String,
        messageID: UUID = UUID()
    ) throws -> ChatPreparedOutgoingTurn {
        let continuationTask = try continuationTaskPolicy.beginResponseTaskIfNeeded()
        let transactionPlan = ChatOutgoingMessageTransactionPlan.newMessage(
            text: text,
            attachments: composerAttachmentStaging.pendingAttachments,
            messageID: messageID
        )
        return try prepare(
            transactionPlan,
            continuationTask: continuationTask
        )
    }

    func prepare(
        _ transactionPlan: ChatOutgoingMessageTransactionPlan
    ) throws -> ChatPreparedOutgoingTurn {
        let continuationTask = try continuationTaskPolicy.beginResponseTaskIfNeeded()
        return try prepare(
            transactionPlan,
            continuationTask: continuationTask
        )
    }

    private func prepare(
        _ transactionPlan: ChatOutgoingMessageTransactionPlan,
        continuationTask: ChatContinuationTask?
    ) throws -> ChatPreparedOutgoingTurn {
        do {
            let responseStream = try turnStarter.startTurn(
                prompt: transactionPlan.prompt,
                attachments: transactionPlan.attachments,
                userMessageID: transactionPlan.messageID,
                replacingUserMessageID: transactionPlan.replacingUserMessageID
            )
            consumeComposerAttachmentsIfNeeded(for: transactionPlan)
            return ChatPreparedOutgoingTurn(
                transactionPlan: transactionPlan,
                preparedStream: ChatPreparedAssistantResponseStream(
                    responseStream: responseStream,
                    continuationTask: continuationTask
                )
            )
        } catch {
            continuationTask?.finish(success: false)
            throw error
        }
    }

    private func consumeComposerAttachmentsIfNeeded(
        for transactionPlan: ChatOutgoingMessageTransactionPlan
    ) {
        guard transactionPlan.consumesComposerAttachments else {
            return
        }

        composerAttachmentStaging.consumePendingAttachments()
    }
}

@MainActor
final class ChatAssistantResponseBackgroundContinuationTaskPolicy: ChatAssistantResponseContinuationTaskPolicy {
    typealias BackgroundRuntimeProvider = @MainActor () -> Bool

    private let continuationTaskBeginner: any ChatAssistantResponseContinuationTaskBeginning
    private let isBackgroundRuntimeEnabled: BackgroundRuntimeProvider

    init(
        continuationTaskBeginner: any ChatAssistantResponseContinuationTaskBeginning,
        isBackgroundRuntimeEnabled: @escaping BackgroundRuntimeProvider
    ) {
        self.continuationTaskBeginner = continuationTaskBeginner
        self.isBackgroundRuntimeEnabled = isBackgroundRuntimeEnabled
    }

    func beginResponseTaskIfNeeded() throws -> ChatContinuationTask? {
        guard isBackgroundRuntimeEnabled() else {
            return nil
        }

        return try continuationTaskBeginner.beginResponseTask()
    }
}

extension ChatRuntime: ChatAssistantResponseTurnStarting {}
extension ChatContinuationTaskCoordinator: ChatAssistantResponseContinuationTaskBeginning {}
extension ChatComposerAttachmentWorkflow: ChatOutgoingTurnComposerAttachmentStaging {}
