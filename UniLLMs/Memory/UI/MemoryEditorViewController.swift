//
//  MemoryEditorViewController.swift
//  UniLLMs
//
//  Hosts saved long-term memory editing.
//

import Observation
import SwiftUI
import UIKit

final class MemoryEditorViewController: UIHostingController<MemoryEditorForm> {
    private let model: MemoryEditorModel
    private let router: MemoryEditorRouter

    init(
        memory: MemoryRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewMemory: Bool = false
    ) {
        let model = MemoryEditorModel(
            memory: memory,
            dependencies: dependencies,
            isNewMemory: isNewMemory
        )
        let router = MemoryEditorRouter()
        self.model = model
        self.router = router
        super.init(rootView: MemoryEditorForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = MemoryEditorModel(
            memory: dependencies.memoryManager.makeMemoryDraft(),
            dependencies: dependencies,
            isNewMemory: true
        )
        let router = MemoryEditorRouter()
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: MemoryEditorForm(model: model, router: router))
        router.hostViewController = self
    }
}

struct MemoryEditorForm: View {
    private let model: MemoryEditorModel
    private let router: MemoryEditorRouter

    fileprivate init(
        model: MemoryEditorModel,
        router: MemoryEditorRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Form {
            Section(String(localized: .memoriesMemory)) {
                SettingsTextEditor(
                    text: memoryTextBinding,
                    placeholder: String(localized: .memoriesMemoryPlaceholder),
                    accessibilityLabel: String(localized: .memoriesMemory),
                    minimumHeight: 220.0
                )
            }
        }
        .navigationTitle(model.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: .generalSave)) {
                    router.saveMemory(model)
                }
                .disabled(!model.canSaveMemory || model.isSaving)
            }
        }
        .settingsAlert(alertBinding)
    }

    private var memoryTextBinding: Binding<String> {
        Binding {
            model.memoryText
        } set: { text in
            model.memoryText = text
        }
    }

    private var alertBinding: Binding<SettingsAlert?> {
        Binding {
            model.alert
        } set: { alert in
            model.alert = alert
        }
    }
}

@MainActor
private final class MemoryEditorRouter {
    weak var hostViewController: UIViewController?

    func saveMemory(_ model: MemoryEditorModel) {
        hostViewController?.view.endEditing(true)

        Task { @MainActor [weak self] in
            guard let self,
                  await model.saveMemory() else {
                return
            }

            hostViewController?.navigationController?.popViewController(animated: true)
        }
    }
}

@MainActor
@Observable
private final class MemoryEditorModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer

    private var memory: MemoryRecord
    private var savedMemory: MemoryRecord
    private var isNewMemory: Bool

    var memoryText: String
    var isSaving = false
    var alert: SettingsAlert?

    init(
        memory: MemoryRecord,
        dependencies: AppDependencyContainer,
        isNewMemory: Bool
    ) {
        self.memory = memory
        savedMemory = memory
        self.isNewMemory = isNewMemory
        self.dependencies = dependencies
        memoryText = memory.text
    }

    var navigationTitle: String {
        isNewMemory ? String(localized: .memoriesNewMemory) : String(localized: .memoriesMemory)
    }

    var canSaveMemory: Bool {
        guard let memoryForSaving else {
            return false
        }

        return isNewMemory || memoryForSaving != savedMemory
    }

    func saveMemory() async -> Bool {
        guard var memoryForSaving else {
            return false
        }

        let now = Date()
        if isNewMemory {
            memoryForSaving.createdAt = now
        }
        memoryForSaving.updatedAt = now
        isSaving = true

        do {
            try await dependencies.memoryManager.saveMemory(memoryForSaving)
            memory = memoryForSaving
            savedMemory = memoryForSaving
            isNewMemory = false
            isSaving = false
            return true
        } catch {
            isSaving = false
            alert = SettingsAlert(
                title: String(localized: .memoriesMemory),
                message: error.localizedDescription
            )
            return false
        }
    }

    private var memoryForSaving: MemoryRecord? {
        let trimmedText = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        var updatedMemory = memory
        updatedMemory.scope = .user
        updatedMemory.text = trimmedText
        return updatedMemory
    }
}
