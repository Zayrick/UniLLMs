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
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(prompts.count, 1)
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard !prompts.isEmpty else {
            return emptyPromptCell()
        }

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

    private func emptyPromptCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = "No System Prompts"
        contentConfiguration.secondaryText = "Tap + to add one"
        contentConfiguration.image = UIImage(systemName: "text.quote")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.selectionStyle = .none
        return cell
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
