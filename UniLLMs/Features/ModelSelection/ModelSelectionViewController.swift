//
//  ModelSelectionViewController.swift
//  UniLLMs
//
//  Displays available provider models and saves the user selected chat model.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class ModelSelectionViewController: UITableViewController, UISearchResultsUpdating {
    private let dependencies: AppDependencyContainer
    private var allProviders: [LLMsProviderRecord] = []
    private var providers: [LLMsProviderRecord] = []
    private var selectedModelSelection: ChatModelSelection?
    private let onSelect: (ChatModelSelection) -> Void
    private let searchController = UISearchController(searchResultsController: nil)

    init(
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        selectedModelSelection: ChatModelSelection?,
        onSelect: @escaping (ChatModelSelection) -> Void
    ) {
        self.dependencies = dependencies
        self.selectedModelSelection = selectedModelSelection
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        dependencies = AppEnvironment.shared.dependencies
        selectedModelSelection = nil
        onSelect = { _ in }
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Select Model"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        configureSearchController()
        reloadProviders()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadProviders()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyModelFilter()
    }

    private func configureSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.placeholder = "Search Models"
        searchController.searchBar.accessibilityLabel = "Search Models"
        navigationItem.searchController = searchController
        navigationItem.preferredSearchBarPlacement = .integratedButton
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func reloadProviders() {
        allProviders = dependencies.providerStore.fetchProviders()
        applyModelFilter()
    }

    private func applyModelFilter() {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            providers = allProviders
            tableView.reloadData()
            return
        }

        let normalizedQuery = query.localizedLowercase
        providers = allProviders.compactMap { provider in
            let displayName = providerDisplayName(provider)
            let providerMatches = displayName.localizedLowercase.contains(normalizedQuery)
            let matchingModels = provider.models.filter { model in
                model.id.localizedLowercase.contains(normalizedQuery)
                    || (model.name?.localizedLowercase.contains(normalizedQuery) ?? false)
            }

            guard providerMatches || !matchingModels.isEmpty else {
                return nil
            }

            var filteredProvider = provider
            filteredProvider.models = providerMatches ? provider.models : matchingModels
            return filteredProvider
        }
        tableView.reloadData()
    }

    private var isFilteringModels: Bool {
        !(searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        providers.isEmpty ? 1 : providers.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard !providers.isEmpty else {
            return 1
        }

        return max(providers[section].models.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !providers.isEmpty else {
            if isFilteringModels && !allProviders.isEmpty {
                return "Search"
            }

            return "Providers"
        }

        return providerDisplayName(providers[section])
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        nil
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard !providers.isEmpty else {
            if isFilteringModels && !allProviders.isEmpty {
                return unavailableCell(
                    title: "No Matches",
                    detail: "Try another model name, model ID, or provider."
                )
            }

            return unavailableCell(
                title: "No LLMs Provider",
                detail: "Add providers in Settings before selecting a model."
            )
        }

        let provider = providers[indexPath.section]
        guard !provider.models.isEmpty else {
            return unavailableCell(
                title: "No Models",
                detail: "Refresh the model list for this provider in Settings."
            )
        }

        let model = provider.models[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = modelTitle(for: model)
        contentConfiguration.secondaryText = modelSubtitle(for: model)
        contentConfiguration.image = UIImage(systemName: "cpu")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = isSelected(model: model, provider: provider) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard !providers.isEmpty else {
            return
        }

        let provider = providers[indexPath.section]
        guard !provider.models.isEmpty else {
            return
        }

        let model = provider.models[indexPath.row]
        let selection = LLMModelSelection(
            providerID: provider.id,
            providerName: providerDisplayName(provider),
            modelID: model.id,
            modelName: model.name
        )
        selectedModelSelection = selection
        onSelect(selection)
        dismiss(animated: true)
    }

    private func unavailableCell(title: String, detail: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = title
        contentConfiguration.secondaryText = detail
        contentConfiguration.image = UIImage(systemName: "exclamationmark.circle")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.selectionStyle = .none
        return cell
    }

    private func isSelected(model: LLMsProviderModel, provider: LLMsProviderRecord) -> Bool {
        selectedModelSelection?.providerID == provider.id
            && selectedModelSelection?.modelID == model.id
    }

    private func providerDisplayName(_ provider: LLMsProviderRecord) -> String {
        dependencies.providerManager.displayName(for: provider)
    }

    private func modelTitle(for model: LLMsProviderModel) -> String {
        normalizedModelName(model.name) ?? model.id
    }

    private func modelSubtitle(for model: LLMsProviderModel) -> String? {
        normalizedModelName(model.name) == nil ? nil : model.id
    }

    private func normalizedModelName(_ name: String?) -> String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
