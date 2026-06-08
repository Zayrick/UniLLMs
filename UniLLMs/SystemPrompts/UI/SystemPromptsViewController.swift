//
//  SystemPromptsViewController.swift
//  UniLLMs
//
//  Displays saved system prompts.
//  Created by Zayrick on 2026/5/19.
//

import Observation
import SwiftUI
import UIKit

final class SystemPromptsViewController: UIHostingController<SystemPromptsListForm> {
    enum Mode {
        case manage
        case select(
            selectedID: UUID?,
            onSelect: (SystemPromptRecord) -> Void,
            onClear: () -> Void
        )
    }

    private let model: SystemPromptsListModel
    private let router: SystemPromptsListRouter

    init(
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        mode: Mode = .manage
    ) {
        let model = SystemPromptsListModel(dependencies: dependencies)
        let router = SystemPromptsListRouter(dependencies: dependencies, mode: mode)
        self.model = model
        self.router = router
        super.init(rootView: SystemPromptsListForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = SystemPromptsListModel(dependencies: dependencies)
        let router = SystemPromptsListRouter(dependencies: dependencies, mode: .manage)
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: SystemPromptsListForm(model: model, router: router))
        router.hostViewController = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshContent()
    }
}

struct SystemPromptsListForm: View {
    private let model: SystemPromptsListModel
    private let router: SystemPromptsListRouter

    fileprivate init(
        model: SystemPromptsListModel,
        router: SystemPromptsListRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Group {
            if model.prompts.isEmpty {
                SystemPromptsEmptyView(
                    isSelectingPrompt: router.isSelectingPrompt,
                    addAction: router.addPrompt
                )
            } else {
                Form {
                    Section {
                        if router.isSelectingPrompt {
                            ForEach(model.prompts) { prompt in
                                promptRow(for: prompt)
                            }
                        } else {
                            ForEach(model.prompts) { prompt in
                                promptRow(for: prompt)
                            }
                            .onDelete(perform: model.deletePrompts)
                        }
                    }
                }
            }
        }
        .navigationTitle(router.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if router.isSelectingPrompt {
                    Button(String(localized: .generalCancel), action: router.cancelSelection)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if router.isSelectingPrompt {
                    if router.selectedPromptID != nil {
                        Button(String(localized: .generalClear), action: router.clearSelection)
                    }
                } else {
                    Button(action: router.addPrompt) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: .generalAdd))
                }
            }
        }
    }

    private func promptRow(for prompt: SystemPromptRecord) -> some View {
        SystemPromptRow(
            prompt: prompt,
            isSelectingPrompt: router.isSelectingPrompt,
            isSelected: prompt.id == router.selectedPromptID
        ) {
            router.openPrompt(prompt)
        }
    }
}

private struct SystemPromptRow: View {
    let prompt: SystemPromptRecord
    let isSelectingPrompt: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(prompt.displayTitle)
                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.tint)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                } else if !isSelectingPrompt {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String? {
        let content = prompt.content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return content.isEmpty ? nil : content
    }
}

private struct SystemPromptsEmptyView: View {
    let isSelectingPrompt: Bool
    let addAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .systemPromptsEmptyTitle), systemImage: "text.quote")
        } description: {
            Text(
                isSelectingPrompt
                    ? String(localized: .systemPromptsEmptySelectDetail)
                    : String(localized: .systemPromptsEmptyManageDetail)
            )
        } actions: {
            if !isSelectingPrompt {
                Button(action: addAction) {
                    Label(String(localized: .systemPromptsAddPrompt), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

@MainActor
private final class SystemPromptsListRouter {
    weak var hostViewController: UIViewController?

    private let dependencies: AppDependencyContainer
    private let mode: SystemPromptsViewController.Mode

    init(
        dependencies: AppDependencyContainer,
        mode: SystemPromptsViewController.Mode
    ) {
        self.dependencies = dependencies
        self.mode = mode
    }

    var navigationTitle: String {
        isSelectingPrompt
            ? String(localized: .systemPromptsChoosePrompt)
            : String(localized: "system_prompts.custom.title")
    }

    var isSelectingPrompt: Bool {
        if case .select = mode {
            return true
        }
        return false
    }

    var selectedPromptID: UUID? {
        if case let .select(selectedID, _, _) = mode {
            return selectedID
        }
        return nil
    }

    func addPrompt() {
        let prompt = dependencies.systemPromptManager.makePromptDraft()
        hostViewController?.navigationController?.pushViewController(
            SystemPromptEditorViewController(
                prompt: prompt,
                dependencies: dependencies,
                isNewPrompt: true
            ),
            animated: true
        )
    }

    func openPrompt(_ prompt: SystemPromptRecord) {
        if case let .select(_, onSelect, _) = mode {
            onSelect(prompt)
            hostViewController?.dismiss(animated: true)
            return
        }

        hostViewController?.navigationController?.pushViewController(
            SystemPromptEditorViewController(
                prompt: prompt,
                dependencies: dependencies
            ),
            animated: true
        )
    }

    func cancelSelection() {
        hostViewController?.dismiss(animated: true)
    }

    func clearSelection() {
        if case let .select(_, _, onClear) = mode {
            onClear()
        }
        hostViewController?.dismiss(animated: true)
    }
}

@MainActor
@Observable
private final class SystemPromptsListModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer
    @ObservationIgnored private var storeObservation: NSObjectProtocol?

    var prompts: [SystemPromptRecord] = []

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        installStoreObserver()
        refreshContent()
    }

    deinit {
        if let storeObservation {
            NotificationCenter.default.removeObserver(storeObservation)
        }
    }

    func refreshContent() {
        prompts = dependencies.systemPromptManager.savedPrompts()
    }

    func deletePrompts(at offsets: IndexSet) {
        let deletedIDs = offsets.compactMap { index in
            prompts.indices.contains(index) ? prompts[index].id : nil
        }
        guard !deletedIDs.isEmpty else {
            return
        }

        prompts.removeAll {
            deletedIDs.contains($0.id)
        }
        deletedIDs.forEach(dependencies.systemPromptManager.deletePrompt)
        refreshContent()
    }

    private func installStoreObserver() {
        storeObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsSystemPromptStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshContent()
            }
        }
    }
}
