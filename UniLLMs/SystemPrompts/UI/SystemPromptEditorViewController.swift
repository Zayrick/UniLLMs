//
//  SystemPromptEditorViewController.swift
//  UniLLMs
//
//  Edits a saved system prompt.
//  Created by Zayrick on 2026/5/19.
//

import Observation
import SwiftUI
import UIKit

final class SystemPromptEditorViewController: UIHostingController<SystemPromptEditorForm> {
    private let model: SystemPromptEditorModel
    private let router: SystemPromptEditorRouter

    init(
        prompt: SystemPromptRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewPrompt: Bool = false
    ) {
        let model = SystemPromptEditorModel(
            prompt: prompt,
            dependencies: dependencies,
            isNewPrompt: isNewPrompt
        )
        let router = SystemPromptEditorRouter()
        self.model = model
        self.router = router
        super.init(rootView: SystemPromptEditorForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = SystemPromptEditorModel(
            prompt: dependencies.systemPromptManager.makePromptDraft(),
            dependencies: dependencies,
            isNewPrompt: true
        )
        let router = SystemPromptEditorRouter()
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: SystemPromptEditorForm(model: model, router: router))
        router.hostViewController = self
    }
}

struct SystemPromptEditorForm: View {
    private let model: SystemPromptEditorModel
    private let router: SystemPromptEditorRouter

    fileprivate init(
        model: SystemPromptEditorModel,
        router: SystemPromptEditorRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    String(localized: .providerFieldName),
                    text: nameBinding,
                    prompt: Text(String(localized: .systemPromptsNamePlaceholder))
                )
                .textInputAutocapitalization(.sentences)
            }

            Section {
                PromptTextEditor(
                    text: promptBinding,
                    placeholder: String(localized: .systemPromptsPromptPlaceholder)
                )
            } header: {
                Text(String(localized: .systemPromptsPrompt))
            } footer: {
                Text(String(localized: .systemPromptsPromptFooter))
            }
        }
        .navigationTitle(model.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "general.save")) {
                    router.savePrompt(model)
                }
                .disabled(!model.canSavePrompt)
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding {
            model.nameText
        } set: { text in
            model.nameText = text
        }
    }

    private var promptBinding: Binding<String> {
        Binding {
            model.promptText
        } set: { text in
            model.promptText = text
        }
    }
}

private struct PromptTextEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Color(uiColor: .placeholderText))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .accessibilityLabel(String(localized: .systemPromptsPrompt))
        }
    }
}

@MainActor
private final class SystemPromptEditorRouter {
    weak var hostViewController: UIViewController?

    func savePrompt(_ model: SystemPromptEditorModel) {
        hostViewController?.view.endEditing(true)
        guard model.savePrompt() else {
            return
        }

        hostViewController?.navigationController?.popViewController(animated: true)
    }
}

@MainActor
@Observable
private final class SystemPromptEditorModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer

    private var prompt: SystemPromptRecord
    private var savedPrompt: SystemPromptRecord
    private var isNewPrompt: Bool

    var nameText: String
    var promptText: String

    init(
        prompt: SystemPromptRecord,
        dependencies: AppDependencyContainer,
        isNewPrompt: Bool
    ) {
        self.prompt = prompt
        savedPrompt = prompt
        self.isNewPrompt = isNewPrompt
        self.dependencies = dependencies
        nameText = prompt.title
        promptText = prompt.content
    }

    var navigationTitle: String {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        return isNewPrompt ? String(localized: .systemPromptsNewPrompt) : savedPrompt.displayTitle
    }

    var canSavePrompt: Bool {
        guard let promptForSaving else {
            return false
        }

        return isNewPrompt || promptForSaving != savedPrompt
    }

    func savePrompt() -> Bool {
        guard var promptForSaving else {
            return false
        }

        promptForSaving.updatedAt = Date()
        prompt = promptForSaving
        dependencies.systemPromptManager.savePrompt(prompt)
        savedPrompt = prompt
        isNewPrompt = false
        return true
    }

    private var promptForSaving: SystemPromptRecord? {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedPrompt.isEmpty else {
            return nil
        }

        var updatedPrompt = prompt
        updatedPrompt.title = trimmedName
        updatedPrompt.content = trimmedPrompt
        return updatedPrompt
    }
}
