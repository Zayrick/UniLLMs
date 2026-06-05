//
//  ChatSystemPromptSelectionWorkflow.swift
//  UniLLMs
//
//  Owns system prompt selection presentation and composer preview updates.
//  Created by Codex on 2026/6/5.
//

import UIKit

@MainActor
final class ChatSystemPromptSelectionWorkflow {
    typealias PromptListBuilder = @MainActor (
        _ selectedID: UUID?,
        _ onSelect: @escaping @MainActor (SystemPromptRecord) -> Void,
        _ onClear: @escaping @MainActor () -> Void
    ) -> UIViewController
    typealias PresentationWrapper = @MainActor (UIViewController) -> UIViewController

    private let selectedSystemPromptID: () -> UUID?
    private let selectedSystemPrompt: () -> SystemPromptRecord?
    private let selectSystemPrompt: (UUID) -> Void
    private let clearSystemPrompt: () -> Void
    private let setComposerDisplay: (ChatSelectedSystemPromptDisplay?) -> Void
    private let buildPromptList: PromptListBuilder
    private let wrapForPresentation: PresentationWrapper

    convenience init(
        dependencies: AppDependencyContainer,
        chatRuntime: ChatRuntime,
        setComposerDisplay: @escaping (ChatSelectedSystemPromptDisplay?) -> Void
    ) {
        self.init(
            selectedSystemPromptID: { chatRuntime.selectedSystemPromptID },
            selectedSystemPrompt: { chatRuntime.selectedSystemPrompt() },
            selectSystemPrompt: { chatRuntime.selectSystemPrompt(id: $0) },
            clearSystemPrompt: { chatRuntime.clearSelectedSystemPrompt() },
            setComposerDisplay: setComposerDisplay,
            buildPromptList: { selectedID, onSelect, onClear in
                SystemPromptsViewController(
                    dependencies: dependencies,
                    mode: .select(
                        selectedID: selectedID,
                        onSelect: onSelect,
                        onClear: onClear
                    )
                )
            },
            wrapForPresentation: { rootViewController in
                ChatPageSheetPresentation.wrapInNavigationController(
                    rootViewController: rootViewController
                )
            }
        )
    }

    init(
        selectedSystemPromptID: @escaping () -> UUID?,
        selectedSystemPrompt: @escaping () -> SystemPromptRecord?,
        selectSystemPrompt: @escaping (UUID) -> Void,
        clearSystemPrompt: @escaping () -> Void,
        setComposerDisplay: @escaping (ChatSelectedSystemPromptDisplay?) -> Void,
        buildPromptList: @escaping PromptListBuilder,
        wrapForPresentation: @escaping PresentationWrapper
    ) {
        self.selectedSystemPromptID = selectedSystemPromptID
        self.selectedSystemPrompt = selectedSystemPrompt
        self.selectSystemPrompt = selectSystemPrompt
        self.clearSystemPrompt = clearSystemPrompt
        self.setComposerDisplay = setComposerDisplay
        self.buildPromptList = buildPromptList
        self.wrapForPresentation = wrapForPresentation
    }

    func makeSelectionViewController() -> UIViewController {
        let rootViewController = buildPromptList(
            selectedSystemPromptID(),
            { [weak self] prompt in
                self?.select(prompt)
            },
            { [weak self] in
                self?.clearSelection()
            }
        )
        return wrapForPresentation(rootViewController)
    }

    func select(_ prompt: SystemPromptRecord) {
        selectSystemPrompt(prompt.id)
        reloadComposerDisplay()
    }

    func clearSelection() {
        clearSystemPrompt()
        reloadComposerDisplay()
    }

    func reloadComposerDisplay() {
        setComposerDisplay(Self.display(from: selectedSystemPrompt()))
    }

    static func display(
        from prompt: SystemPromptRecord?
    ) -> ChatSelectedSystemPromptDisplay? {
        prompt.map {
            ChatSelectedSystemPromptDisplay(
                id: $0.id,
                title: $0.displayTitle
            )
        }
    }
}
