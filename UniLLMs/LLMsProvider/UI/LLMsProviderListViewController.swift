//
//  LLMsProviderListViewController.swift
//  UniLLMs
//
//  Hosts provider configuration management.
//  Created by Zayrick on 2026/5/11.
//

import Observation
import SwiftUI
import UIKit

final class LLMsProviderViewController: UIHostingController<LLMsProviderListView> {
    private let model: LLMsProviderListModel
    private let router: LLMsProviderListRouter

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        let model = LLMsProviderListModel(dependencies: dependencies)
        let router = LLMsProviderListRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(rootView: LLMsProviderListView(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = LLMsProviderListModel(dependencies: dependencies)
        let router = LLMsProviderListRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: LLMsProviderListView(model: model, router: router))
        router.hostViewController = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshProviders()
    }
}

struct LLMsProviderListView: View {
    private let model: LLMsProviderListModel
    private let router: LLMsProviderListRouter

    fileprivate init(
        model: LLMsProviderListModel,
        router: LLMsProviderListRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Group {
            if model.providers.isEmpty {
                emptyContent
            } else {
                providersList
            }
        }
        .navigationTitle(String(localized: .settingsRowProvidersTitle))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.providers.count > 1 {
                    EditButton()
                }

                addProviderMenu(iconOnly: true)
            }
        }
        .settingsAlert(alertBinding)
    }

    private var providersList: some View {
        List {
            Section(String(localized: .providersSectionProviders)) {
                ForEach(model.providers) { provider in
                    Button {
                        router.editProvider(provider)
                    } label: {
                        HStack(spacing: 12.0) {
                            SettingsRowLabel(
                                title: model.displayName(for: provider),
                                symbolName: "globe",
                                tintColor: .systemBlue
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
                .onDelete(perform: model.deleteProviders)
                .onMove(perform: model.moveProviders)
            }
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(String(localized: .providersNoProviders), systemImage: "globe")
        } description: {
            Text(String(localized: .providersNoProvidersDetail))
        } actions: {
            addProviderMenu(iconOnly: false)
                .buttonStyle(.borderedProminent)
        }
    }

    private func addProviderMenu(iconOnly: Bool) -> some View {
        Menu {
            ForEach(model.providerMenuItems) { item in
                Button(item.displayName) {
                    router.addProvider(kind: item.kind, model: model)
                }
            }
        } label: {
            if iconOnly {
                Image(systemName: "plus")
            } else {
                Label(String(localized: .providersAddProvider), systemImage: "plus")
            }
        }
        .accessibilityLabel(String(localized: .providersAddProvider))
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
private final class LLMsProviderListRouter {
    weak var hostViewController: UIViewController?

    private let dependencies: AppDependencyContainer

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
    }

    func addProvider(kind: LLMsProviderKind, model: LLMsProviderListModel) {
        guard let provider = model.makeProvider(kind: kind) else {
            return
        }

        hostViewController?.navigationController?.pushViewController(
            ProviderConfigurationViewController(
                provider: provider,
                dependencies: dependencies,
                isNewProvider: true
            ),
            animated: true
        )
    }

    func editProvider(_ provider: LLMsProviderRecord) {
        hostViewController?.navigationController?.pushViewController(
            ProviderConfigurationViewController(provider: provider, dependencies: dependencies),
            animated: true
        )
    }
}

@MainActor
@Observable
private final class LLMsProviderListModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer

    var providers: [LLMsProviderRecord] = []
    var alert: SettingsAlert?

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        refreshProviders()
    }

    var providerMenuItems: [LLMsProviderMenuItem] {
        dependencies.providerRegistry.adapters.map {
            LLMsProviderMenuItem(kind: $0.kind, displayName: $0.displayName)
        }
    }

    func refreshProviders() {
        providers = dependencies.providerStore.fetchProviders()
    }

    func displayName(for provider: LLMsProviderRecord) -> String {
        dependencies.providerManager.displayName(for: provider)
    }

    func makeProvider(kind: LLMsProviderKind) -> LLMsProviderRecord? {
        do {
            let provider = try dependencies.providerManager.makeProviderDraft(kind: kind)
            guard !dependencies.providerManager.configurationFields(for: kind).isEmpty else {
                dependencies.providerStore.saveProvider(provider)
                refreshProviders()
                return nil
            }

            return provider
        } catch {
            alert = SettingsAlert(
                title: String(localized: .providersErrorUnableToAdd),
                message: error.localizedDescription
            )
            return nil
        }
    }

    func deleteProviders(at offsets: IndexSet) {
        let deletedIDs = offsets.compactMap { index in
            providers.indices.contains(index) ? providers[index].id : nil
        }
        guard !deletedIDs.isEmpty else {
            return
        }

        withAnimation {
            providers.removeAll {
                deletedIDs.contains($0.id)
            }
        }
        deletedIDs.forEach(dependencies.providerStore.deleteProvider)
        refreshProviders()
    }

    func moveProviders(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else {
            return
        }

        let previousProviders = providers
        providers.move(fromOffsets: source, toOffset: destination)
        persistProviderOrder(from: previousProviders, to: providers)
        refreshProviders()
    }

    private func persistProviderOrder(
        from previousProviders: [LLMsProviderRecord],
        to reorderedProviders: [LLMsProviderRecord]
    ) {
        var workingProviders = previousProviders
        for targetIndex in reorderedProviders.indices {
            let desiredID = reorderedProviders[targetIndex].id
            guard let currentIndex = workingProviders.firstIndex(where: { $0.id == desiredID }),
                  currentIndex != targetIndex else {
                continue
            }

            dependencies.providerStore.moveProvider(
                from: currentIndex,
                to: targetIndex
            )
            let movedProvider = workingProviders.remove(at: currentIndex)
            workingProviders.insert(movedProvider, at: targetIndex)
        }
    }
}

private struct LLMsProviderMenuItem: Identifiable {
    var id: LLMsProviderKind {
        kind
    }

    let kind: LLMsProviderKind
    let displayName: String
}
