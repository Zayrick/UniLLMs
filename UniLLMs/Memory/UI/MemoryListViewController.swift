//
//  MemoryListViewController.swift
//  UniLLMs
//
//  Hosts saved memory review and editing.
//

import Observation
import SwiftUI
import UIKit

final class MemoryListViewController: UIHostingController<MemoryListView> {
    private let model: MemoryListModel
    private let router: MemoryListRouter

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        let model = MemoryListModel(dependencies: dependencies)
        let router = MemoryListRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(rootView: MemoryListView(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = MemoryListModel(dependencies: dependencies)
        let router = MemoryListRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: MemoryListView(model: model, router: router))
        router.hostViewController = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.reloadContent()
    }
}

struct MemoryListView: View {
    private let model: MemoryListModel
    private let router: MemoryListRouter

    fileprivate init(
        model: MemoryListModel,
        router: MemoryListRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Group {
            if model.visibleMemories.isEmpty {
                emptyContent
            } else {
                memoriesList
            }
        }
        .navigationTitle(String(localized: .memoriesMemory))
        .searchable(
            text: searchTextBinding,
            prompt: String(localized: .memoriesSearchSavedMemories)
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                actionsMenu
            }
        }
        .confirmationDialog(
            String(localized: .memoriesClearAllConfirmationTitle),
            isPresented: clearAllConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: .memoriesClearMemories), role: .destructive) {
                model.clearAllMemories()
            }
            Button(String(localized: .generalCancel), role: .cancel) {}
        } message: {
            Text(model.clearAllConfirmationMessage)
        }
        .settingsAlert(alertBinding)
        .task {
            model.reloadContent()
        }
    }

    private var memoriesList: some View {
        List {
            ForEach(model.visibleMemories) { memory in
                Button {
                    router.editMemory(memory)
                } label: {
                    HStack(spacing: 12.0) {
                        SettingsRowLabel(
                            title: model.displayText(for: memory),
                            subtitle: String(localized: .generalUpdatedFormat(memory.updatedAt.formatted(date: .abbreviated, time: .shortened))),
                            symbolName: "brain.head.profile",
                            tintColor: .systemTeal,
                            subtitleLineLimit: 1
                        )
                        Spacer(minLength: 8.0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: model.deleteVisibleMemories)
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "brain.head.profile")
        } description: {
            Text(emptyDetail)
        } actions: {
            if model.memories.isEmpty {
                Button {
                    router.addMemory()
                } label: {
                    Label(String(localized: .memoriesAddMemory), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                router.addMemory()
            } label: {
                Label(String(localized: .memoriesAddMemory), systemImage: "plus")
            }

            Button(role: .destructive) {
                model.showClearAllConfirmation()
            } label: {
                Label(String(localized: .memoriesClearAll), systemImage: "trash")
            }
            .disabled(model.memories.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(String(localized: .generalMore))
    }

    private var emptyTitle: String {
        model.memories.isEmpty
            ? String(localized: .memoriesEmptyNoSavedTitle)
            : String(localized: .memoriesEmptyNoMatchingTitle)
    }

    private var emptyDetail: String {
        model.memories.isEmpty
            ? String(localized: .memoriesEmptyNoSavedDetail)
            : String(localized: .memoriesEmptyNoMatchingDetail)
    }

    private var searchTextBinding: Binding<String> {
        Binding {
            model.searchText
        } set: { text in
            model.searchText = text
        }
    }

    private var clearAllConfirmationBinding: Binding<Bool> {
        Binding {
            model.isShowingClearAllConfirmation
        } set: { isShowing in
            model.isShowingClearAllConfirmation = isShowing
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
private final class MemoryListRouter {
    weak var hostViewController: UIViewController?

    private let dependencies: AppDependencyContainer

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
    }

    func addMemory() {
        hostViewController?.navigationController?.pushViewController(
            MemoryEditorViewController(
                memory: dependencies.memoryManager.makeMemoryDraft(),
                dependencies: dependencies,
                isNewMemory: true
            ),
            animated: true
        )
    }

    func editMemory(_ memory: MemoryRecord) {
        hostViewController?.navigationController?.pushViewController(
            MemoryEditorViewController(
                memory: memory,
                dependencies: dependencies
            ),
            animated: true
        )
    }
}

@MainActor
@Observable
private final class MemoryListModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer
    @ObservationIgnored private var storeObservation: NSObjectProtocol?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    var memories: [MemoryRecord] = []
    var searchText = ""
    var isShowingClearAllConfirmation = false
    var alert: SettingsAlert?

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        installStoreObserver()
        reloadContent()
    }

    deinit {
        reloadTask?.cancel()
        clearTask?.cancel()
        if let storeObservation {
            NotificationCenter.default.removeObserver(storeObservation)
        }
    }

    var visibleMemories: [MemoryRecord] {
        MemoryTextSearch.filtered(memories, matching: searchText)
    }

    var clearAllConfirmationMessage: String {
        memories.count == 1
            ? String(localized: .memoriesClearAllConfirmationOneMessage)
            : String(localized: .memoriesClearAllConfirmationCountMessageFormat(memories.count))
    }

    func reloadContent() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let memories = try await dependencies.memoryManager.savedMemories(scope: .user)
                guard !Task.isCancelled else {
                    return
                }

                self.memories = memories
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                memories = []
                alert = SettingsAlert(
                    title: String(localized: .memoriesMemory),
                    message: error.localizedDescription
                )
            }
        }
    }

    func showClearAllConfirmation() {
        guard !memories.isEmpty else {
            return
        }

        isShowingClearAllConfirmation = true
    }

    func deleteVisibleMemories(at offsets: IndexSet) {
        let deletedIDs = offsets.compactMap { index in
            visibleMemories.indices.contains(index) ? visibleMemories[index].id : nil
        }
        guard !deletedIDs.isEmpty else {
            return
        }

        memories.removeAll {
            deletedIDs.contains($0.id)
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                for id in deletedIDs {
                    try await dependencies.memoryManager.deleteMemory(id: id)
                }
            } catch {
                alert = SettingsAlert(
                    title: String(localized: .generalDelete),
                    message: error.localizedDescription
                )
                reloadContent()
            }
        }
    }

    func clearAllMemories() {
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await dependencies.memoryManager.deleteAllMemories(scope: .user)
            } catch {
                alert = SettingsAlert(
                    title: String(localized: .memoriesClearAll),
                    message: error.localizedDescription
                )
                reloadContent()
            }
        }
    }

    func displayText(for memory: MemoryRecord) -> String {
        let text = memory.text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? String(localized: .memoriesUntitledMemory) : text
    }

    private func installStoreObserver() {
        storeObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMemoryStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadContent()
            }
        }
    }
}
