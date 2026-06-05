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
        static var addTitle: String { String(localized: .providerConfigurationAddModel) }
        static var modelIDTitle: String { String(localized: .providerConfigurationModelId) }
        static let modelIDPlaceholder = "gpt-4.1-mini"
    }

    private enum ReuseIdentifier {
        static let readOnlyModelCell = "ReadOnlyModelCell"
    }

    private let dependencies: AppDependencyContainer
    private var saveButtonItem: UIBarButtonItem?
    private var draft: LLMsProviderConfigurationDraft
    private var isNewProvider: Bool
    private var isLoadingModels = false
    private var didStartInitialModelLoad = false

    private var provider: LLMsProviderRecord {
        draft.provider
    }

    private var configurationFields: [LLMsProviderConfigurationField] {
        dependencies.providerManager.configurationFields(for: provider.kind)
    }

    private var modelSource: LLMsProviderModelSource? {
        draft.modelSource
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
        self.isNewProvider = isNewProvider
        self.dependencies = dependencies
        draft = LLMsProviderConfigurationDraft(
            provider: provider,
            modelSource: dependencies.providerManager.modelSource(for: provider.kind)
        )
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        self.dependencies = dependencies
        let provider = (try? dependencies.providerManager.makeDefaultProviderDraft())
            ?? LLMsProviderRecord(
                kind: LLMsProviderKind(rawValue: ""),
                name: "",
                configuration: LLMsProviderConfiguration(),
                createdAt: dependencies.clock.now
            )
        draft = LLMsProviderConfigurationDraft(
            provider: provider,
            modelSource: dependencies.providerManager.modelSource(for: provider.kind)
        )
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
        tableView.register(
            ModelsSectionHeaderView.self,
            forHeaderFooterViewReuseIdentifier: ModelsSectionHeaderView.reuseIdentifier
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
            case .remote:
                return provider.models.count
            case .manual:
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
            return String(localized: .providerConfigurationSectionConfiguration)
        case .models:
            guard modelSource != .remote else {
                return nil
            }

            return String(localized: .providerConfigurationSectionModels)
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section),
              section == .models,
              modelSource == .remote else {
            return nil
        }

        return modelRefreshDetailText
    }

    override func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        guard let section = Section(rawValue: section),
              section == .models,
              modelSource == .remote,
              let headerView = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: ModelsSectionHeaderView.reuseIdentifier
              ) as? ModelsSectionHeaderView else {
            return nil
        }

        headerView.configure(title: String(localized: .providerConfigurationSectionModels), isLoading: isLoadingModels)
        headerView.onRefresh = { [weak self] in
            self?.refreshModels()
        }
        return headerView
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
            guard configurationFields.indices.contains(indexPath.row),
                  configurationFields[indexPath.row].inputKind != .toggle else {
                return
            }

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
        let deleteAction = UIContextualAction(style: .destructive, title: String(localized: .generalDelete)) { [weak self] _, _, completion in
            guard let self,
                  draft.removeManualModel(at: modelIndex) else {
                completion(false)
                return
            }

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
        guard configurationFields.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }

        let field = configurationFields[indexPath.row]
        guard field.inputKind != .toggle else {
            return toggleConfigurationCell(for: field)
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderTextFieldCell.reuseIdentifier,
            for: indexPath
        ) as? ProviderTextFieldCell else {
            return UITableViewCell()
        }

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

    private func toggleConfigurationCell(for field: LLMsProviderConfigurationField) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = field.title
        cell.contentConfiguration = contentConfiguration

        let toggle = UISwitch()
        toggle.isOn = booleanValue(for: field)
        toggle.addAction(
            UIAction { [weak self, weak toggle, field] _ in
                guard let toggle else {
                    return
                }

                self?.setValue(toggle.isOn ? "true" : "false", for: field)
            },
            for: .valueChanged
        )
        cell.accessoryView = toggle
        cell.selectionStyle = .none
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
        guard provider.models.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }

        let model = provider.models[indexPath.row]
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
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.readOnlyModelCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.readOnlyModelCell)
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

        return String(localized: .generalUpdatedFormat(updatedDateFormatter.string(from: updatedAt)))
    }

    private var manualModelsDetailText: String? {
        let modelCount = manualModelCount
        guard modelCount > 0 else {
            return nil
        }

        return modelCount == 1
            ? String(localized: .providerConfigurationModelCountOne)
            : String(localized: .providerConfigurationModelCountFormat(modelCount))
    }

    private var manualModelCount: Int {
        draft.manualModelCount
    }

    private func value(for field: LLMsProviderConfigurationField) -> String {
        draft.value(for: field)
    }

    private func booleanValue(for field: LLMsProviderConfigurationField) -> Bool {
        draft.booleanValue(for: field)
    }

    private func setValue(_ text: String, for field: LLMsProviderConfigurationField) {
        draft.setValue(text, for: field)

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
        case .toggle:
            return .default
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
        case .toggle:
            return nil
        }
    }

    private func handleModelSelection(at indexPath: IndexPath) {
        guard let modelSource else {
            return
        }

        switch modelSource {
        case .manual where indexPath.row == 0:
            appendManualModelRow()
        case .manual:
            (tableView.cellForRow(at: indexPath) as? ProviderTextFieldCell)?.activateTextField()
        case .remote, .`static`:
            return
        }
    }

    private func appendManualModelRow() {
        let modelIndex = draft.appendManualModel()

        let insertedIndexPath = IndexPath(
            row: modelIndex + 1,
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
        let oldModelCount = manualModelCount
        guard draft.setManualModelID(text, at: modelIndex) else {
            return
        }

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
            title: String(localized: .providerConfigurationErrorUnableToRefreshModels),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: String(localized: .generalOk), style: .default))
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
                let modelsUpdatedAt = dependencies.clock.now
                draft.replaceRemoteModels(models, updatedAt: modelsUpdatedAt)
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
        let validatedProvider = draft.providerForSaving(updatedAt: dependencies.clock.now)
        do {
            try dependencies.providerManager.validateChatConfiguration(for: validatedProvider)
        } catch {
            presentConfigurationSaveError(error)
            return
        }

        dependencies.providerStore.saveProvider(validatedProvider)
        isNewProvider = false
        draft.markSaved(validatedProvider)
        title = dependencies.providerManager.displayName(for: provider)
        updateSaveButtonState()
        navigationController?.popViewController(animated: true)
    }

    private func presentConfigurationSaveError(_ error: Error) {
        guard presentedViewController == nil else {
            return
        }

        let alertController = UIAlertController(
            title: String(localized: .providerConfigurationErrorUnableToSaveProvider),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: String(localized: .generalOk), style: .default))
        present(alertController, animated: true)
    }

    private func updateSaveButtonState() {
        navigationItem.rightBarButtonItem = canSaveConfiguration ? saveButtonItem : nil
    }

    private var canSaveConfiguration: Bool {
        draft.canSave(
            isNewProvider: isNewProvider,
            hasRequiredConfigurationFields: hasRequiredConfigurationFields
        )
    }

    private var hasRequiredConfigurationFields: Bool {
        dependencies.providerManager.hasRequiredConfigurationFields(for: provider)
    }

    private func modelTitle(for model: LLMsProviderModel) -> String {
        draft.modelTitle(for: model)
    }

    private func modelSubtitle(for model: LLMsProviderModel) -> String? {
        draft.modelSubtitle(for: model)
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

private final class ModelsSectionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "ModelsSectionHeaderView"

    var onRefresh: (() -> Void)?

    private lazy var titleContentView = UIListContentView(
        configuration: defaultContentConfiguration()
    )

    private let refreshButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = String(localized: .providerConfigurationRefresh)
        configuration.buttonSize = .mini

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = String(localized: .providerConfigurationRefreshModels)
        return button
    }()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        onRefresh = nil
        configure(title: nil, isLoading: false)
    }

    func configure(title: String?, isLoading: Bool) {
        var titleConfiguration = defaultContentConfiguration()
        titleConfiguration.text = title
        titleContentView.configuration = titleConfiguration

        var buttonConfiguration = refreshButton.configuration ?? .plain()
        buttonConfiguration.title = isLoading
            ? String(localized: .providerConfigurationRefreshing)
            : String(localized: .providerConfigurationRefresh)
        buttonConfiguration.image = nil
        buttonConfiguration.buttonSize = .mini
        buttonConfiguration.showsActivityIndicator = false
        refreshButton.configuration = buttonConfiguration
        refreshButton.isEnabled = !isLoading
        refreshButton.accessibilityValue = isLoading ? String(localized: .providerConfigurationRefreshing) : nil
    }

    private func configureLayout() {
        titleContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleContentView)

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.addTarget(self, action: #selector(refreshModels), for: .touchUpInside)
        contentView.addSubview(refreshButton)

        NSLayoutConstraint.activate([
            titleContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            titleContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleContentView.trailingAnchor.constraint(
                lessThanOrEqualTo: refreshButton.leadingAnchor,
                constant: -8
            ),
            titleContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            refreshButton.centerYAnchor.constraint(equalTo: titleContentView.centerYAnchor),
            refreshButton.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            refreshButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    @objc private func refreshModels() {
        onRefresh?()
    }
}
