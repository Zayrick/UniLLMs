//
//  ChatComposerAddWorkflow.swift
//  UniLLMs
//
//  Owns composer add sheet presentation and action routing.
//  Created by Codex on 2026/6/5.
//

import UIKit

@MainActor
final class ChatComposerAddWorkflow {
    typealias AddSheetBuilder = @MainActor () -> ComposerAddSheetViewController
    typealias SourceViewProvider = @MainActor () -> UIView?
    typealias PresentationApplier = @MainActor (UIViewController) -> Void

    private let sourceView: SourceViewProvider
    private let presentSystemPromptSelection: () -> Void
    private let presentCameraPicker: () -> Void
    private let presentPhotoLibraryPicker: () -> Void
    private let presentDocumentPicker: () -> Void
    private let makeAddSheet: AddSheetBuilder
    private let applyPresentation: PresentationApplier

    init(
        sourceView: @escaping SourceViewProvider,
        presentSystemPromptSelection: @escaping () -> Void,
        presentCameraPicker: @escaping () -> Void,
        presentPhotoLibraryPicker: @escaping () -> Void,
        presentDocumentPicker: @escaping () -> Void,
        makeAddSheet: @escaping AddSheetBuilder = { ComposerAddSheetViewController() },
        applyPresentation: @escaping PresentationApplier = { viewController in
            ChatPageSheetPresentation.apply(
                to: viewController,
                detentStyle: .mediumAndLarge,
                showsGrabber: true
            )
        }
    ) {
        self.sourceView = sourceView
        self.presentSystemPromptSelection = presentSystemPromptSelection
        self.presentCameraPicker = presentCameraPicker
        self.presentPhotoLibraryPicker = presentPhotoLibraryPicker
        self.presentDocumentPicker = presentDocumentPicker
        self.makeAddSheet = makeAddSheet
        self.applyPresentation = applyPresentation
    }

    func makeAddSheetViewController() -> UIViewController {
        let addViewController = makeAddSheet()
        applyPresentation(addViewController)
        addViewController.preferredTransition = .zoom { [sourceView] _ in
            sourceView()
        }
        addViewController.onAction = { [weak self] action in
            self?.route(action)
        }
        return addViewController
    }

    func route(_ action: ComposerAddSheetViewController.Action) {
        switch action {
        case .systemPrompt:
            presentSystemPromptSelection()
        case .camera:
            presentCameraPicker()
        case .photoLibrary:
            presentPhotoLibraryPicker()
        case .files:
            presentDocumentPicker()
        }
    }
}
