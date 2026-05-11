//
//  LLMsProviderConfigurationViewController.swift
//  UniLLMs
//
//  Displays provider configuration fields supplied by adapters and refreshes provider model lists.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class LLMsProviderConfigurationViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case configuration
        case models
    }

    private let dependencies: AppDependencyContainer
    private var saveButtonItem: UIBarButtonItem?
    private var provider: LLMsProviderRecord
    private var savedProvider: LLMsProviderRecord
    private var isNewProvider: Bool
    private var isLoadingModels = false
    private var didStartInitialModelLoad = false

    private var configurationFields: [LLMsProviderConfigurationField] {
        dependencies.providerManager.configurationFields(for: provider.kind)
    }

    private lazy var updatedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        provider: LLMsProviderRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewProvider: Bool = false
    ) {
        self.provider = provider
        savedProvider = provider
        self.isNewProvider = isNewProvider
        self.dependencies = dependencies
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        self.dependencies = dependencies
        provider = (try? dependencies.providerManager.makeProviderDraft(kind: .openRouter))
            ?? dependencies.providerStore.makeOpenRouterProviderDraft()
        savedProvider = provider
        isNewProvider = true
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = dependencies.providerManager.displayName(for: provider)
        tableView.register(
            ProviderTextFieldCell.self,
            forCellReuseIdentifier: ProviderTextFieldCell.reuseIdentifier
        )
        configureSaveButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !isNewProvider,
              !didStartInitialModelLoad else {
            return
        }

        didStartInitialModelLoad = true
        refreshModels()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .configuration:
            return configurationFields.count
        case .models:
            return provider.models.count + 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }

        switch section {
        case .configuration:
            return "Configuration"
        case .models:
            return "Models"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .configuration:
            return configurationCell(for: indexPath)
        case .models:
            return modelCell(for: indexPath)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch section {
        case .configuration:
            (tableView.cellForRow(at: indexPath) as? ProviderTextFieldCell)?.activateTextField()
        case .models where indexPath.row == 0:
            refreshModels()
        case .models:
            return
        }
    }

    private func configurationCell(for indexPath: IndexPath) -> UITableViewCell {
        guard configurationFields.indices.contains(indexPath.row),
              let cell = tableView.dequeueReusableCell(
                withIdentifier: ProviderTextFieldCell.reuseIdentifier,
                for: indexPath
              ) as? ProviderTextFieldCell else {
            return UITableViewCell()
        }

        let field = configurationFields[indexPath.row]
        cell.configure(
            title: field.title,
            text: value(for: field),
            placeholder: field.placeholder,
            isSecureTextEntry: field.inputKind == .secret,
            keyboardType: keyboardType(for: field.inputKind),
            textContentType: textContentType(for: field.inputKind)
        )
        cell.onTextChange = { [weak self] text in
            self?.setValue(text, for: field)
        }
        return cell
    }

    private func modelCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var contentConfiguration = UIListContentConfiguration.subtitleCell()
            contentConfiguration.text = isLoadingModels ? "Refreshing Model List" : "Refresh Model List"
            contentConfiguration.secondaryText = modelRefreshDetailText
            contentConfiguration.image = UIImage(systemName: "arrow.clockwise")
            cell.contentConfiguration = contentConfiguration
            cell.selectionStyle = isLoadingModels ? .none : .default

            if isLoadingModels {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
            }

            return cell
        }

        let model = provider.models[indexPath.row - 1]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = UIListContentConfiguration.subtitleCell()
        contentConfiguration.text = model.name
        contentConfiguration.secondaryText = model.id
        contentConfiguration.image = UIImage(systemName: "cpu")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.selectionStyle = .none
        return cell
    }

    private var modelRefreshDetailText: String? {
        guard let updatedAt = provider.modelsUpdatedAt else {
            return nil
        }

        return "Updated \(updatedDateFormatter.string(from: updatedAt))"
    }

    private func value(for field: LLMsProviderConfigurationField) -> String {
        switch field.valueKey {
        case .providerName:
            return provider.name
        case .apiKey:
            return provider.configuration.apiKey
        case .apiBase:
            return provider.configuration.apiBase
        case let .extra(key):
            return provider.configuration.extra[key] ?? ""
        }
    }

    private func setValue(_ text: String, for field: LLMsProviderConfigurationField) {
        switch field.valueKey {
        case .providerName:
            provider.name = text
            title = text.isEmpty ? dependencies.providerManager.displayName(for: provider) : text
        case .apiKey:
            provider.configuration.apiKey = text
        case .apiBase:
            provider.configuration.apiBase = text
        case let .extra(key):
            provider.configuration.extra[key] = text
        }

        updateSaveButtonState()
    }

    private func keyboardType(for inputKind: LLMsProviderConfigurationField.InputKind) -> UIKeyboardType {
        switch inputKind {
        case .plain:
            return .default
        case .secret:
            return .asciiCapable
        case .url:
            return .URL
        }
    }

    private func textContentType(
        for inputKind: LLMsProviderConfigurationField.InputKind
    ) -> UITextContentType? {
        switch inputKind {
        case .plain:
            return .name
        case .secret:
            return .password
        case .url:
            return .URL
        }
    }

    private func presentModelLoadError(_ error: Error) {
        guard presentedViewController == nil else {
            return
        }

        let alertController = UIAlertController(
            title: "Unable to Refresh Models",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    private func refreshModels() {
        guard !isLoadingModels else {
            return
        }

        isLoadingModels = true
        reloadModelsSection(animated: true)

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let models = try await dependencies.providerManager.fetchModels(for: provider)
                let modelsUpdatedAt = Date()
                provider.models = models
                provider.modelsUpdatedAt = modelsUpdatedAt
                savedProvider.models = models
                savedProvider.modelsUpdatedAt = modelsUpdatedAt
                if !isNewProvider {
                    dependencies.providerStore.updateProviderModels(
                        id: provider.id,
                        models: models,
                        modelsUpdatedAt: modelsUpdatedAt
                    )
                }
            } catch {
                presentModelLoadError(error)
            }

            isLoadingModels = false
            updateSaveButtonState()
            reloadModelsSection(animated: true)
        }
    }

    private func configureSaveButton() {
        let saveItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveConfiguration)
        )
        saveButtonItem = saveItem
        updateSaveButtonState()
    }

    @objc private func saveConfiguration() {
        view.endEditing(true)
        dependencies.providerStore.saveProvider(provider)
        isNewProvider = false
        savedProvider = provider
        title = dependencies.providerManager.displayName(for: provider)
        updateSaveButtonState()
        navigationController?.popViewController(animated: true)
    }

    private func updateSaveButtonState() {
        navigationItem.rightBarButtonItem = canSaveConfiguration ? saveButtonItem : nil
    }

    private var canSaveConfiguration: Bool {
        hasUnsavedConfigurationChanges && hasRequiredConfigurationFields
    }

    private var hasRequiredConfigurationFields: Bool {
        configurationFields.allSatisfy {
            !value(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var hasUnsavedConfigurationChanges: Bool {
        provider.name != savedProvider.name
            || provider.configuration != savedProvider.configuration
    }

    private func reloadModelsSection(animated: Bool) {
        let sectionIndexSet = IndexSet(integer: Section.models.rawValue)
        tableView.reloadSections(sectionIndexSet, with: animated ? .automatic : .none)
    }
}

typealias ProviderConfigurationViewController = LLMsProviderConfigurationViewController
