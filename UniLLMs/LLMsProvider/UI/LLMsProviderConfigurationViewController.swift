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

    private enum ModelRows {
        static let addTitle = "Add Model"
        static let modelIDTitle = "Model ID"
        static let modelIDPlaceholder = "gpt-4.1-mini"
        static let refreshTitle = "Refresh Model List"
        static let loadingTitle = "Refreshing Model List"
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

    private var modelSource: LLMsProviderModelSource? {
        dependencies.providerManager.modelSource(for: provider.kind)
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
        provider = (try? dependencies.providerManager.makeDefaultProviderDraft())
            ?? LLMsProviderRecord(
                kind: LLMsProviderKind(rawValue: ""),
                name: "",
                configuration: LLMsProviderConfiguration()
            )
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

        guard let modelSource,
              case .remote = modelSource,
              !isNewProvider,
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
            guard let modelSource else {
                return 0
            }

            switch modelSource {
            case .remote, .manual:
                return provider.models.count + 1
            case .`static`:
                return provider.models.count
            }
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
        case .models:
            handleModelSelection(at: indexPath)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let section = Section(rawValue: indexPath.section),
              section == .models,
              let modelSource,
              case .manual = modelSource,
              indexPath.row > 0 else {
            return nil
        }

        let modelIndex = indexPath.row - 1
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self,
                  provider.models.indices.contains(modelIndex) else {
                completion(false)
                return
            }

            provider.models.remove(at: modelIndex)
            updateSaveButtonState()
            tableView.performBatchUpdates {
                tableView.deleteRows(at: [indexPath], with: .fade)
            } completion: { [weak self] _ in
                self?.reloadManualModelsSummary()
            }
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
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
        guard let modelSource else {
            return UITableViewCell()
        }

        switch modelSource {
        case .remote:
            return remoteModelCell(for: indexPath)
        case .manual:
            return manualModelCell(for: indexPath)
        case .`static`:
            return staticModelCell(for: indexPath)
        }
    }

    private func remoteModelCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            var contentConfiguration = cell.defaultContentConfiguration()
            contentConfiguration.text = isLoadingModels ? ModelRows.loadingTitle : ModelRows.refreshTitle
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
        return readOnlyModelCell(for: model)
    }

    private func manualModelCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            var contentConfiguration = cell.defaultContentConfiguration()
            contentConfiguration.text = ModelRows.addTitle
            contentConfiguration.secondaryText = manualModelsDetailText
            contentConfiguration.image = UIImage(systemName: "plus.circle")
            cell.contentConfiguration = contentConfiguration
            cell.selectionStyle = .default
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderTextFieldCell.reuseIdentifier,
            for: indexPath
        ) as? ProviderTextFieldCell else {
            return UITableViewCell()
        }

        let model = provider.models[indexPath.row - 1]
        cell.configure(
            title: ModelRows.modelIDTitle,
            text: model.id,
            placeholder: ModelRows.modelIDPlaceholder,
            isSecureTextEntry: false,
            keyboardType: .asciiCapable,
            textContentType: nil
        )
        cell.onTextChange = { [weak self, weak cell] text in
            guard let self,
                  let cell,
                  let currentIndexPath = self.tableView.indexPath(for: cell) else {
                return
            }

            self.setManualModelID(text, at: currentIndexPath.row - 1)
        }
        return cell
    }

    private func staticModelCell(for indexPath: IndexPath) -> UITableViewCell {
        let model = provider.models[indexPath.row]
        return readOnlyModelCell(for: model)
    }

    private func readOnlyModelCell(for model: LLMsProviderModel) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = modelTitle(for: model)
        contentConfiguration.secondaryText = modelSubtitle(for: model)
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

    private var manualModelsDetailText: String? {
        let modelCount = manualModelCount
        guard modelCount > 0 else {
            return nil
        }

        return modelCount == 1 ? "1 Model" : "\(modelCount) Models"
    }

    private var manualModelCount: Int {
        provider.models
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private func value(for field: LLMsProviderConfigurationField) -> String {
        provider.configurationValue(for: field.binding)
    }

    private func setValue(_ text: String, for field: LLMsProviderConfigurationField) {
        provider.setConfigurationValue(text, for: field.binding)

        switch field.binding {
        case .providerName:
            title = text.isEmpty ? dependencies.providerManager.displayName(for: provider) : text
        case .configurationValue(_):
            break
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

    private func handleModelSelection(at indexPath: IndexPath) {
        guard let modelSource else {
            return
        }

        switch modelSource {
        case .remote where indexPath.row == 0:
            refreshModels()
        case .manual where indexPath.row == 0:
            appendManualModelRow()
        case .manual:
            (tableView.cellForRow(at: indexPath) as? ProviderTextFieldCell)?.activateTextField()
        case .remote, .`static`:
            return
        }
    }

    private func appendManualModelRow() {
        provider.models.append(
            LLMsProviderModel(
                id: "",
                name: nil,
                contextLength: nil
            )
        )

        let insertedIndexPath = IndexPath(
            row: provider.models.count,
            section: Section.models.rawValue
        )
        updateSaveButtonState()
        tableView.insertRows(at: [insertedIndexPath], with: .automatic)
        tableView.scrollToRow(at: insertedIndexPath, at: .middle, animated: true)

        DispatchQueue.main.async { [weak self] in
            (self?.tableView.cellForRow(at: insertedIndexPath) as? ProviderTextFieldCell)?
                .activateTextField()
        }
    }

    private func setManualModelID(_ text: String, at modelIndex: Int) {
        guard provider.models.indices.contains(modelIndex) else {
            return
        }

        let oldModelCount = manualModelCount
        provider.models[modelIndex].id = text
        provider.models[modelIndex].name = normalizedModelName(provider.models[modelIndex].name)

        updateSaveButtonState()

        if oldModelCount != manualModelCount {
            reloadManualModelsSummary()
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
        guard let modelSource,
              case .remote = modelSource,
              !isLoadingModels else {
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
        provider = providerForSaving
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
        hasRequiredConfigurationFields && (isNewProvider || hasUnsavedChanges)
    }

    private var hasRequiredConfigurationFields: Bool {
        dependencies.providerManager.hasRequiredConfigurationFields(for: provider)
    }

    private var hasUnsavedChanges: Bool {
        providerForComparison(provider) != providerForComparison(savedProvider)
    }

    private var providerForSaving: LLMsProviderRecord {
        var normalizedRecord = normalizedProvider(provider)
        guard hasManualModelListChanges else {
            return normalizedRecord
        }

        normalizedRecord.modelsUpdatedAt = Date()
        return normalizedRecord
    }

    private func normalizedProvider(_ provider: LLMsProviderRecord) -> LLMsProviderRecord {
        var normalizedRecord = provider
        normalizedRecord.models = provider.models.compactMap { model in
            let trimmedID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                return nil
            }

            return LLMsProviderModel(
                id: trimmedID,
                name: normalizedModelName(model.name),
                contextLength: model.contextLength
            )
        }
        return normalizedRecord
    }

    private func providerForComparison(_ provider: LLMsProviderRecord) -> LLMsProviderRecord {
        var normalizedRecord = normalizedProvider(provider)
        if modelSource == .manual {
            normalizedRecord.modelsUpdatedAt = normalizedProvider(savedProvider).modelsUpdatedAt
        }
        return normalizedRecord
    }

    private var hasManualModelListChanges: Bool {
        guard modelSource == .manual else {
            return false
        }

        return normalizedProvider(provider).models != normalizedProvider(savedProvider).models
    }

    private func normalizedModelName(_ name: String?) -> String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func modelTitle(for model: LLMsProviderModel) -> String {
        normalizedModelName(model.name) ?? model.id
    }

    private func modelSubtitle(for model: LLMsProviderModel) -> String? {
        normalizedModelName(model.name) == nil ? nil : model.id
    }

    private func reloadManualModelsSummary() {
        let addIndexPath = IndexPath(row: 0, section: Section.models.rawValue)
        guard tableView.indexPathsForVisibleRows?.contains(addIndexPath) == true else {
            return
        }

        tableView.reloadRows(at: [addIndexPath], with: .none)
    }

    private func reloadModelsSection(animated: Bool) {
        let sectionIndexSet = IndexSet(integer: Section.models.rawValue)
        tableView.reloadSections(sectionIndexSet, with: animated ? .automatic : .none)
    }
}

typealias ProviderConfigurationViewController = LLMsProviderConfigurationViewController
