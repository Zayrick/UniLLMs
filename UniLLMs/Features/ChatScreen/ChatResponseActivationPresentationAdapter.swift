//
//  ChatResponseActivationPresentationAdapter.swift
//  UniLLMs
//
//  Applies assistant response activation state to chat screen presentation controls.
//

import Foundation

struct ChatResponseActivationPresentation: Equatable {
    var isComposerSendingEnabled: Bool
    var isStreamingResponseActive: Bool
    var isBackgroundFlowing: Bool

    static let active = ChatResponseActivationPresentation(
        isComposerSendingEnabled: false,
        isStreamingResponseActive: true,
        isBackgroundFlowing: true
    )

    static let inactive = ChatResponseActivationPresentation(
        isComposerSendingEnabled: true,
        isStreamingResponseActive: false,
        isBackgroundFlowing: false
    )
}

@MainActor
struct ChatResponseActivationPresentationAdapter {
    private let setComposerSendingEnabled: (Bool) -> Void
    private let setComposerStreamingActive: (Bool, Bool) -> Void
    private let setBackgroundFlowing: (Bool, Bool) -> Void
    private let updateHeader: (Bool) -> Void

    init(
        setComposerSendingEnabled: @escaping (Bool) -> Void,
        setComposerStreamingActive: @escaping (Bool, Bool) -> Void,
        setBackgroundFlowing: @escaping (Bool, Bool) -> Void,
        updateHeader: @escaping (Bool) -> Void
    ) {
        self.setComposerSendingEnabled = setComposerSendingEnabled
        self.setComposerStreamingActive = setComposerStreamingActive
        self.setBackgroundFlowing = setBackgroundFlowing
        self.updateHeader = updateHeader
    }

    func prepareActivation(animated: Bool) {
        apply(.active, animated: animated)
    }

    func completeActivation(animated: Bool) {
        updateHeader(animated)
    }

    func deactivate(animated: Bool) {
        apply(.inactive, animated: animated)
        updateHeader(animated)
    }

    private func apply(
        _ presentation: ChatResponseActivationPresentation,
        animated: Bool
    ) {
        setComposerSendingEnabled(presentation.isComposerSendingEnabled)
        setComposerStreamingActive(presentation.isStreamingResponseActive, animated)
        setBackgroundFlowing(presentation.isBackgroundFlowing, animated)
    }
}
