//
//  ChatMessageActionPresentation.swift
//  UniLLMs
//
//  Builds message action view controllers with the chat screen's presentation policy.
//

import UIKit

enum ChatMessageActionPresentation {
    static func makeEditor(
        text: String,
        attachments: [ChatAttachment],
        onSubmit: @escaping (String) -> Void
    ) -> UIViewController {
        let editorViewController = MessageEditViewController(
            text: text,
            allowsEmptyText: !attachments.isEmpty
        )
        editorViewController.onSubmit = { [weak editorViewController] editedText in
            editorViewController?.dismiss(animated: true) {
                onSubmit(editedText)
            }
        }

        return makePageSheet(rootViewController: editorViewController)
    }

    static func makeRevisionHistory(
        revisions: [ChatMessageRevision],
        onSelectRevision: @escaping (ChatMessageRevision) -> Void
    ) -> UIViewController {
        let historyViewController = MessageRevisionHistoryViewController(revisions: revisions)
        let navigationController = makePageSheet(rootViewController: historyViewController)
        historyViewController.onSelectRevision = { [weak navigationController] revision in
            navigationController?.dismiss(animated: true) {
                onSelectRevision(revision)
            }
        }

        return navigationController
    }

    private static func makePageSheet(rootViewController: UIViewController) -> UINavigationController {
        return ChatPageSheetPresentation.wrapInNavigationController(
            rootViewController: rootViewController,
            detentStyle: .mediumAndLarge,
            showsGrabber: true
        )
    }
}
