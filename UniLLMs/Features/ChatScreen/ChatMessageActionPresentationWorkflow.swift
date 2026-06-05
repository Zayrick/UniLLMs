//
//  ChatMessageActionPresentationWorkflow.swift
//  UniLLMs
//
//  Owns message editor and revision-history presentation routing.
//

import UIKit

@MainActor
struct ChatMessageActionPresentationWorkflow {
    typealias EditorFactory = (
        _ text: String,
        _ attachments: [ChatAttachment],
        _ onSubmit: @escaping (String) -> Void
    ) -> UIViewController
    typealias RevisionHistoryFactory = (
        _ revisions: [ChatMessageRevision],
        _ onSelectRevision: @escaping (ChatMessageRevision) -> Void
    ) -> UIViewController

    var isResponseActive: () -> Bool
    var isPresentingModal: () -> Bool
    var containsMessage: (_ messageID: UUID) -> Bool
    var messageRevisions: (_ messageID: UUID) -> [ChatMessageRevision]
    var endEditing: () -> Void
    var makeEditor: EditorFactory
    var makeRevisionHistory: RevisionHistoryFactory
    var presentViewController: (UIViewController) -> Void
    var presentActionFailure: (ChatMessageActionPolicy.FailureReason) -> Void
    var resendEditedMessage: (_ messageID: UUID, _ text: String, _ attachments: [ChatAttachment]) -> Void
    var switchToMessageRevision: (_ messageID: UUID, _ revisionID: UUID) -> Void

    func presentEditor(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) {
        let decision = editorPresentationDecision(messageID: messageID)
        guard shouldPresent(decision) else {
            return
        }

        endEditing()
        let editorViewController = makeEditor(text, attachments) { submittedText in
            resendEditedMessage(messageID, submittedText, attachments)
        }
        presentViewController(editorViewController)
    }

    func presentRevisionHistory(messageID: UUID) {
        let preparation = revisionHistoryPreparation(messageID: messageID)
        guard shouldPresent(preparation.decision) else {
            return
        }

        endEditing()
        let historyViewController = makeRevisionHistory(preparation.revisions) { revision in
            switchToMessageRevision(messageID, revision.id)
        }
        presentViewController(historyViewController)
    }

    private func editorPresentationDecision(
        messageID: UUID
    ) -> ChatMessageActionPolicy.PresentationDecision {
        guard !isResponseActive() else {
            return .fail(.responseInProgress)
        }

        guard !isPresentingModal() else {
            return .ignore
        }

        return ChatMessageActionPolicy.editPresentationDecision(
            isResponseActive: false,
            isPresentingModal: false,
            containsMessage: containsMessage(messageID)
        )
    }

    private func revisionHistoryPreparation(
        messageID: UUID
    ) -> (
        decision: ChatMessageActionPolicy.PresentationDecision,
        revisions: [ChatMessageRevision]
    ) {
        guard !isPresentingModal() else {
            return (.ignore, [])
        }

        guard containsMessage(messageID) else {
            return (.fail(.messageUnavailable), [])
        }

        let revisions = messageRevisions(messageID)
        let decision = ChatMessageActionPolicy.revisionHistoryPresentationDecision(
            isPresentingModal: false,
            containsMessage: true,
            hasRevisions: !revisions.isEmpty
        )
        return (decision, revisions)
    }

    private func shouldPresent(_ decision: ChatMessageActionPolicy.PresentationDecision) -> Bool {
        switch decision {
        case .present:
            return true
        case .ignore:
            return false
        case let .fail(reason):
            presentActionFailure(reason)
            return false
        }
    }
}
