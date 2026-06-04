//
//  SystemPromptsViewController.swift
//  UniLLMs
//
//  Displays saved system prompts.
//  Created by Zayrick on 2026/5/19.
//

import UIKit

final class SystemPromptsViewController: UITableViewController {
    enum Mode {
        case manage
        case select(
            selectedID: UUID?,
            onSelect: (SystemPromptRecord) -> Void,
            onClear: () -> Void
        )
    }

    private let dependencies: AppDependencyContainer
    private let mode: Mode
    private var prompts: [SystemPromptRecord] = []
    private var storeObservation: NSObjectProtocol?

    private enum ReuseIdentifier {
        static let promptCell = "SystemPromptCell"
    }

    init(
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        mode: Mode = .manage
    ) {
        self.dependencies = dependencies
        self.mode = mode
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        dependencies = AppEnvironment.shared.dependencies
        mode = .manage
        super.init(coder: coder)
    }

    deinit {
        if let storeObservation {
            NotificationCenter.default.removeObserver(storeObservation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = isSelectingPrompt
            ? String(localized: .systemPromptsChoosePrompt)
            : String(localized: "system_prompts.custom.title")
        configureCancelButtonIfNeeded()
        configureAddButton()
        configureClearButtonIfNeeded()
        installStoreObserver()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadContent()
    }

    private func configureAddButton() {
        guard !isSelectingPrompt else {
            return
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addPrompt)
        )
    }

    private func configureClearButtonIfNeeded() {
        guard isSelectingPrompt,
              selectedPromptID != nil else {
            return
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: .generalClear),
            style: .plain,
            target: self,
            action: #selector(clearSelection)
        )
    }

    private func configureCancelButtonIfNeeded() {
        guard isSelectingPrompt else {
            return
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelSelection)
        )
    }

    private func installStoreObserver() {
        storeObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsSystemPromptStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadContent()
        }
    }

    private func reloadContent() {
        prompts = dependencies.systemPromptManager.savedPrompts()
        tableView.reloadData()
        setNeedsUpdateContentUnavailableConfiguration()
    }

    @objc private func addPrompt() {
        let prompt = dependencies.systemPromptManager.makePromptDraft()
        navigationController?.pushViewController(
            SystemPromptEditorViewController(
                prompt: prompt,
                dependencies: dependencies,
                isNewPrompt: true
            ),
            animated: true
        )
    }

    @objc private func cancelSelection() {
        dismiss(animated: true)
    }

    @objc private func clearSelection() {
        if case let .select(_, _, onClear) = mode {
            onClear()
        }
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        prompts.count
    }

    override func updateContentUnavailableConfiguration(
        using state: UIContentUnavailableConfigurationState
    ) {
        guard prompts.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }

        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "text.quote")
        configuration.text = String(localized: .systemPromptsEmptyTitle)
        configuration.secondaryText = isSelectingPrompt
            ? String(localized: .systemPromptsEmptySelectDetail)
            : String(localized: .systemPromptsEmptyManageDetail)
        if !isSelectingPrompt {
            configuration.button = addPromptButtonConfiguration()
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
                self?.addPrompt()
            }
        }
        contentUnavailableConfiguration = configuration
    }

    private func addPromptButtonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: .systemPromptsAddPrompt)
        configuration.image = UIImage(systemName: "plus")
        configuration.imagePadding = 6
        return configuration
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        return promptCell(for: indexPath)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard prompts.indices.contains(indexPath.row) else {
            return
        }

        if case let .select(_, onSelect, _) = mode {
            onSelect(prompts[indexPath.row])
            dismiss(animated: true)
            return
        }

        navigationController?.pushViewController(
            SystemPromptEditorViewController(
                prompt: prompts[indexPath.row],
                dependencies: dependencies
            ),
            animated: true
        )
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isSelectingPrompt else {
            return nil
        }

        guard prompts.indices.contains(indexPath.row) else {
            return nil
        }

        let deleteAction = UIContextualAction(style: .destructive, title: String(localized: .generalDelete)) { [weak self] _, _, completion in
            guard let self,
                  prompts.indices.contains(indexPath.row) else {
                completion(false)
                return
            }

            dependencies.systemPromptManager.deletePrompt(id: prompts[indexPath.row].id)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func promptCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.promptCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.promptCell)
        let prompt = prompts[indexPath.row]
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = prompt.displayTitle
        contentConfiguration.secondaryText = subtitle(for: prompt)
        contentConfiguration.secondaryTextProperties.numberOfLines = 1
        contentConfiguration.image = UIImage(systemName: "text.quote")
        cell.contentConfiguration = contentConfiguration
        if prompt.id == selectedPromptID {
            cell.accessoryType = .checkmark
            cell.accessibilityTraits.insert(.selected)
        } else {
            cell.accessoryType = isSelectingPrompt ? .none : .disclosureIndicator
            cell.accessibilityTraits.remove(.selected)
        }
        return cell
    }

    private func subtitle(for prompt: SystemPromptRecord) -> String? {
        let content = prompt.content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return content.isEmpty ? nil : content
    }

    private var isSelectingPrompt: Bool {
        if case .select = mode {
            return true
        }
        return false
    }

    private var selectedPromptID: UUID? {
        if case let .select(selectedID, _, _) = mode {
            return selectedID
        }
        return nil
    }
}
