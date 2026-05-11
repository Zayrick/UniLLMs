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
            barButtonSystemItem: .add,
            target: self,
            action: #selector(presentProviderPicker)
        )
    }

    private func reloadProviders() {
        providers = dependencies.providerStore.fetchProviders()
        tableView.reloadData()
    }

    @objc private func presentProviderPicker() {
        let adapters = dependencies.providerRegistry.adapters
        guard adapters.count > 1 else {
            presentNewProvider(kind: adapters.first?.kind ?? .openRouter)
            return
        }

        let alertController = UIAlertController(
            title: "Add Provider",
            message: nil,
            preferredStyle: .actionSheet
        )
        adapters.forEach { adapter in
            alertController.addAction(
                UIAlertAction(title: adapter.displayName, style: .default) { [weak self] _ in
                    self?.presentNewProvider(kind: adapter.kind)
                }
            )
        }
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alertController.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alertController, animated: true)
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
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let provider = providers[indexPath.row]

        var contentConfiguration = UIListContentConfiguration.subtitleCell()
        contentConfiguration.text = dependencies.providerManager.displayName(for: provider)
        contentConfiguration.secondaryText = provider.configuration.apiBase
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
