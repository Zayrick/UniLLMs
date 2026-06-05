//
//  ChatResponsePresentationState.swift
//  UniLLMs
//
//  Tracks the presentation policy for an in-flight assistant response.
//

import Foundation

nonisolated struct ChatResponsePresentationState: Equatable {
    nonisolated enum FailurePolicy: Equatable {
        case restoreDraftIfNoVisibleProgress
        case keepResponseView
    }

    var prompt: String
    var attachments: [ChatAttachment]
    var failurePolicy: FailurePolicy
    private(set) var hasVisibleProgress = false

    static func newMessage(
        prompt: String,
        attachments: [ChatAttachment]
    ) -> ChatResponsePresentationState {
        ChatResponsePresentationState(
            prompt: prompt,
            attachments: attachments,
            failurePolicy: .restoreDraftIfNoVisibleProgress
        )
    }

    static func replacementMessage(
        prompt: String,
        attachments: [ChatAttachment]
    ) -> ChatResponsePresentationState {
        ChatResponsePresentationState(
            prompt: prompt,
            attachments: attachments,
            failurePolicy: .keepResponseView
        )
    }

    var shouldRestoreDraftAfterFailure: Bool {
        failurePolicy == .restoreDraftIfNoVisibleProgress && !hasVisibleProgress
    }

    mutating func recordVisibleProgress(from delta: ChatResponseDelta) {
        guard !delta.displayParts.isEmpty else {
            return
        }

        hasVisibleProgress = true
    }
}
