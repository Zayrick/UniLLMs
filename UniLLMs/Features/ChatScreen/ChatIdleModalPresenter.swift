//
//  ChatIdleModalPresenter.swift
//  UniLLMs
//
//  Created by Codex on 2026/6/5.
//

import UIKit

@MainActor
struct ChatIdleModalPresenter {
    typealias ModalPresentationState = @MainActor () -> Bool
    typealias EndEditing = @MainActor () -> Void
    typealias ViewControllerPresenter = @MainActor (UIViewController) -> Void
    typealias ViewControllerBuilder = @MainActor () -> UIViewController?

    private let modalPresentationState: ModalPresentationState
    private let endEditingAction: EndEditing
    private let viewControllerPresenter: ViewControllerPresenter

    var isPresentingModal: Bool {
        modalPresentationState()
    }

    init(
        isPresentingModal: @escaping ModalPresentationState,
        endEditing: @escaping EndEditing,
        presentViewController: @escaping ViewControllerPresenter
    ) {
        modalPresentationState = isPresentingModal
        endEditingAction = endEditing
        viewControllerPresenter = presentViewController
    }

    @discardableResult
    func presentIfIdle(
        endEditing shouldEndEditing: Bool = true,
        makeViewController: ViewControllerBuilder
    ) -> Bool {
        guard !isPresentingModal else {
            return false
        }

        guard let viewController = makeViewController() else {
            return false
        }

        if shouldEndEditing {
            endEditing()
        }
        presentPrepared(viewController)
        return true
    }

    func endEditing() {
        endEditingAction()
    }

    func presentPrepared(_ viewController: UIViewController) {
        viewControllerPresenter(viewController)
    }
}
