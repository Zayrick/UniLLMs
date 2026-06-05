//
//  ChatMessageActionPolicy.swift
//  UniLLMs
//
//  Decides message editing, revision, and resend actions from chat screen state.
//  Created by Codex on 2026/6/5.
//

import Foundation

struct ChatMessageActionPolicy: Equatable {
    enum FailureReason: Equatable {
        case responseInProgress
        case messageUnavailable
    }

    enum PresentationDecision: Equatable {
        case present
        case ignore
        case fail(FailureReason)
    }

    enum RevisionSwitchDecision: Equatable {
        case switchRevision
        case fail(FailureReason)
    }

    enum ResendDecision: Equatable {
        case resend
        case ignore
        case fail(FailureReason)
    }

    static func editPresentationDecision(
        isResponseActive: Bool,
        isPresentingModal: Bool,
        containsMessage: Bool
    ) -> PresentationDecision {
        guard !isResponseActive else {
            return .fail(.responseInProgress)
        }

        guard !isPresentingModal else {
            return .ignore
        }

        guard containsMessage else {
            return .fail(.messageUnavailable)
        }

        return .present
    }

    static func revisionHistoryPresentationDecision(
        isPresentingModal: Bool,
        containsMessage: Bool,
        hasRevisions: Bool
    ) -> PresentationDecision {
        guard !isPresentingModal else {
            return .ignore
        }

        guard containsMessage else {
            return .fail(.messageUnavailable)
        }

        guard hasRevisions else {
            return .ignore
        }

        return .present
    }

    static func revisionSwitchDecision(
        isResponseActive: Bool
    ) -> RevisionSwitchDecision {
        isResponseActive ? .fail(.responseInProgress) : .switchRevision
    }

    static func editedMessageText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resendDecision(
        isResponseActive: Bool,
        text: String,
        hasAttachments: Bool,
        containsMessage: Bool
    ) -> ResendDecision {
        guard !isResponseActive else {
            return .fail(.responseInProgress)
        }

        guard !text.isEmpty || hasAttachments else {
            return .ignore
        }

        guard containsMessage else {
            return .fail(.messageUnavailable)
        }

        return .resend
    }
}
