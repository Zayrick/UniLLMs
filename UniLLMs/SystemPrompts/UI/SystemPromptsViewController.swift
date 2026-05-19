//
//  SystemPromptsViewController.swift
//  UniLLMs
//
//  Displays saved system prompts.
//  Created by Codex on 2026/5/19.
//

import UIKit

final class SystemPromptsViewController: UITableViewController {
    private let dependencies: AppDependencyContainer
    private var prompts: [SystemPromptRecord] = []
    private var storeObservation: NSObjectProtocol?

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        self.dependencies = dependencies
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        dependencies = AppEnvironment.shared.dependencies
        super.init(coder: coder)
    }

    deinit {
        if let storeObservation {
            NotificationCenter.default.removeObserver(storeObservation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "System Prompts"
        configureAddButton()
        installStoreObserver()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadContent()
    }

    private func configureAddButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addPrompt)
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

    override func numberOfSections(in tableView: UITableView) -> Int {
        prompts.isEmpty ? 0 : 1
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
        configuration.text = "No System Prompts"
        configuration.secondaryText = "Save reusable instructions and apply them when starting new conversations."
        configuration.button = addPromptButtonConfiguration()
        configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
            self?.addPrompt()
        }
        contentUnavailableConfiguration = configuration
    }

    private func addPromptButtonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Add Prompt"
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
        guard prompts.indices.contains(indexPath.row) else {
            return nil
        }

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
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
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let prompt = prompts[indexPath.row]
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = prompt.displayTitle
        contentConfiguration.secondaryText = subtitle(for: prompt)
        contentConfiguration.image = UIImage(systemName: "text.quote")
        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func subtitle(for prompt: SystemPromptRecord) -> String? {
        let content = prompt.content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return content.isEmpty ? nil : content
    }
}
