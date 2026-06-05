//
//  ChatPageSheetPresentation.swift
//  UniLLMs
//
//  Applies the chat screen's standard page-sheet presentation policy.
//

import UIKit

enum ChatPageSheetPresentation {
    enum DetentStyle {
        case automatic
        case mediumAndLarge
    }

    static func wrapInNavigationController(
        rootViewController: UIViewController,
        detentStyle: DetentStyle = .automatic,
        showsGrabber: Bool = false
    ) -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: rootViewController)
        apply(
            to: navigationController,
            detentStyle: detentStyle,
            showsGrabber: showsGrabber
        )
        return navigationController
    }

    static func apply(
        to viewController: UIViewController,
        detentStyle: DetentStyle = .automatic,
        showsGrabber: Bool = false
    ) {
        viewController.modalPresentationStyle = .pageSheet
        guard let sheet = viewController.sheetPresentationController else {
            return
        }

        switch detentStyle {
        case .automatic:
            break
        case .mediumAndLarge:
            sheet.detents = [.medium(), .large()]
        }
        sheet.prefersGrabberVisible = showsGrabber
    }
}
