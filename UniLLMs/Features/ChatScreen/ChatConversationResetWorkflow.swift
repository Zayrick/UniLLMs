//
//  ChatConversationResetWorkflow.swift
//  UniLLMs
//
//  Owns conversation reset cleanup and presentation effects.
//

import Foundation

@MainActor
struct ChatConversationResetWorkflow {
    enum Intent: Equatable {
        case startNewConversation(isPrivacyModeEnabled: Bool)
        case togglePrivacyMode(isPrivacyModeEnabled: Bool)
        case deleteCurrentHistorySession
    }

    var clearPendingAttachments: (_ deleteFiles: Bool) -> Void
    var resetConversation: (_ privacyMode: Bool?) -> [ChatAttachment]
    var discardPrivateModeAttachments: ([ChatAttachment]) -> Void
    var removeChatContent: () -> Void
    var reloadSelectedSystemPrompt: () -> Void
    var lockMessagesToBottom: () -> Void
    var updateHeader: () -> Void
    var reloadHistorySessions: (_ selectedSessionID: UUID?) -> Void

    func perform(_ intent: Intent) {
        switch intent {
        case let .startNewConversation(isPrivacyModeEnabled):
            if isPrivacyModeEnabled {
                clearPendingAttachments(true)
            }
            performReset(privacyMode: isPrivacyModeEnabled)
        case let .togglePrivacyMode(isPrivacyModeEnabled):
            clearPendingAttachments(true)
            performReset(privacyMode: !isPrivacyModeEnabled)
        case .deleteCurrentHistorySession:
            performReset(privacyMode: nil)
        }
    }

    private func performReset(privacyMode: Bool?) {
        let discardedAttachments = resetConversation(privacyMode)
        discardPrivateModeAttachments(discardedAttachments)
        removeChatContent()
        reloadSelectedSystemPrompt()
        lockMessagesToBottom()
        updateHeader()
        reloadHistorySessions(nil)
    }
}
