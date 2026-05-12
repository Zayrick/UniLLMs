//
//  LLMsProviderListViewController.swift
//  UniLLMs
//
//  Displays, adds, and deletes LLM provider configurations with new providers added through the registry.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class LLMsProviderViewController: UITableViewController {
    private let dependencies: AppDependencyContainer
    private var providers: [LLMsProviderRecord] = []

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        self.dependencies = dependencies
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        dependencies = AppEnvironment.shared.dependencies
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "LLMs Provider"

        configureAddButton()
        reloadProviders()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadProviders()
    }

    private func configureAddButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add,
            menu: providerMenu()
        )
    }

    private func reloadProviders() {
        providers = dependencies.providerStore.fetchProviders()
        tableView.reloadData()
    }

    private func providerMenu() -> UIMenu {
        let actions = dependencies.providerRegistry.adapters.map { adapter in
            UIAction(title: adapter.displayName) { [weak self] _ in
                self?.presentNewProvider(kind: adapter.kind)
            }
        }

        return UIMenu(title: "Add Provider", children: actions)
    }

    private func presentNewProvider(kind: LLMsProviderKind) {
        do {
            let provider = try dependencies.providerManager.makeProviderDraft(kind: kind)
            navigationController?.pushViewController(
                ProviderConfigurationViewController(
                    provider: provider,
                    dependencies: dependencies,
                    isNewProvider: true
                ),
                animated: true
            )
        } catch {
            presentProviderError(error)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        providers.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Providers"
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let provider = providers[indexPath.row]

        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = dependencies.providerManager.displayName(for: provider)
        contentConfiguration.secondaryText = dependencies.providerManager.configurationSummary(for: provider)
        contentConfiguration.image = UIImage(systemName: "globe")

        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let provider = providers[indexPath.row]
        navigationController?.pushViewController(
            ProviderConfigurationViewController(provider: provider, dependencies: dependencies),
            animated: true
        )
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self,
                  indexPath.row < providers.count else {
                completion(false)
                return
            }

            let provider = providers.remove(at: indexPath.row)
            dependencies.providerStore.deleteProvider(id: provider.id)
            tableView.performBatchUpdates {
                tableView.deleteRows(at: [indexPath], with: .fade)
            } completion: { _ in
                completion(true)
            }
        }
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func presentProviderError(_ error: Error) {
        let alertController = UIAlertController(
            title: "Unable to Add Provider",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}
