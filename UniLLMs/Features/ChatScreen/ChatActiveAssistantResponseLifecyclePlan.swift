//
//  ChatActiveAssistantResponseLifecyclePlan.swift
//  UniLLMs
//
//  Plans active assistant response side effects without owning UIKit objects.
//

import Foundation

nonisolated struct ChatActiveAssistantResponseLifecyclePlan: Equatable {
    nonisolated enum Action: Equatable {
        case recordVisibleProgress(ChatResponseDelta)
        case reportDelta(ChatResponseDelta)
        case appendDisplayParts([ChatResponseDisplayPart])
        case clearActiveResponseView
        case finishActiveResponseView
        case clearActiveResponseContext
        case deactivatePresentation
        case playCancellationFeedback
    }

    let actions: [Action]

    static func received(delta: ChatResponseDelta) -> ChatActiveAssistantResponseLifecyclePlan {
        guard !delta.isEmpty else {
            return ChatActiveAssistantResponseLifecyclePlan(actions: [])
        }

        var actions: [Action] = [
            .recordVisibleProgress(delta),
            .reportDelta(delta)
        ]
        if !delta.displayParts.isEmpty {
            actions.append(.appendDisplayParts(delta.displayParts))
        }
        return ChatActiveAssistantResponseLifecyclePlan(actions: actions)
    }

    static func presentedFailure(
        shouldClearActiveResponseView: Bool
    ) -> ChatActiveAssistantResponseLifecyclePlan {
        guard shouldClearActiveResponseView else {
            return ChatActiveAssistantResponseLifecyclePlan(actions: [])
        }

        return ChatActiveAssistantResponseLifecyclePlan(actions: [.clearActiveResponseView])
    }

    static func cancelled(
        didCancel: Bool
    ) -> ChatActiveAssistantResponseLifecyclePlan {
        guard didCancel else {
            return ChatActiveAssistantResponseLifecyclePlan(actions: [])
        }

        return ChatActiveAssistantResponseLifecyclePlan(actions: [.playCancellationFeedback])
    }

    static func finished(
        hasActiveResponseView: Bool
    ) -> ChatActiveAssistantResponseLifecyclePlan {
        var actions: [Action] = []
        if hasActiveResponseView {
            actions.append(.finishActiveResponseView)
        }
        actions.append(.clearActiveResponseView)
        actions.append(.clearActiveResponseContext)
        actions.append(.deactivatePresentation)
        return ChatActiveAssistantResponseLifecyclePlan(actions: actions)
    }
}
