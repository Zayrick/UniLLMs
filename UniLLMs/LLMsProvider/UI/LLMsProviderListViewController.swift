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
        configureProviderReordering()
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

    private func configureProviderReordering() {
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
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
            guard !dependencies.providerManager.configurationFields(for: kind).isEmpty else {
                dependencies.providerStore.saveProvider(provider)
                reloadProviders()
                return
            }

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

        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = dependencies.providerManager.displayName(for: provider)
        contentConfiguration.image = UIImage(systemName: "globe")

        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = .disclosureIndicator
        cell.showsReorderControl = providers.count > 1
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

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0 && providers.count > 1
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        moveProvider(from: sourceIndexPath, to: destinationIndexPath)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard !providers.isEmpty else {
            return proposedDestinationIndexPath
        }

        let row = min(max(proposedDestinationIndexPath.row, 0), providers.count - 1)
        return IndexPath(row: row, section: 0)
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

    @discardableResult
    private func moveProvider(from sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) -> Bool {
        guard sourceIndexPath.section == 0,
              destinationIndexPath.section == 0,
              providers.indices.contains(sourceIndexPath.row),
              providers.indices.contains(destinationIndexPath.row),
              sourceIndexPath != destinationIndexPath else {
            return false
        }

        let provider = providers.remove(at: sourceIndexPath.row)
        providers.insert(provider, at: destinationIndexPath.row)
        dependencies.providerStore.moveProvider(
            from: sourceIndexPath.row,
            to: destinationIndexPath.row
        )
        return true
    }

    private func dragItem(for provider: LLMsProviderRecord) -> UIDragItem {
        let itemProvider = NSItemProvider(object: provider.id.uuidString as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = provider.id
        return dragItem
    }

    private func providerMoveDestinationIndexPath(from proposedIndexPath: IndexPath?) -> IndexPath? {
        guard !providers.isEmpty else {
            return nil
        }

        let proposedRow = proposedIndexPath?.row ?? providers.count - 1
        let row = min(max(proposedRow, 0), providers.count - 1)
        return IndexPath(row: row, section: 0)
    }

    private func containsProviderDragItem(_ session: UIDropSession) -> Bool {
        session.localDragSession?.items.contains { item in
            item.localObject is UUID
        } == true
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

extension LLMsProviderViewController: UITableViewDragDelegate {
    func tableView(
        _ tableView: UITableView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard indexPath.section == 0,
              providers.count > 1,
              providers.indices.contains(indexPath.row) else {
            return []
        }

        return [dragItem(for: providers[indexPath.row])]
    }

    func tableView(
        _ tableView: UITableView,
        dragSessionIsRestrictedToDraggingApplication session: UIDragSession
    ) -> Bool {
        true
    }

    func tableView(
        _ tableView: UITableView,
        dragSessionAllowsMoveOperation session: UIDragSession
    ) -> Bool {
        true
    }
}

extension LLMsProviderViewController: UITableViewDropDelegate {
    func tableView(
        _ tableView: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UITableViewDropProposal {
        guard providers.count > 1,
              containsProviderDragItem(session) else {
            return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let item = coordinator.items.first(where: { $0.dragItem.localObject is UUID }),
              let sourceIndexPath = item.sourceIndexPath,
              let providerID = item.dragItem.localObject as? UUID,
              sourceIndexPath.section == 0,
              providers.indices.contains(sourceIndexPath.row),
              providers[sourceIndexPath.row].id == providerID,
              let destinationIndexPath = providerMoveDestinationIndexPath(
                from: coordinator.destinationIndexPath
              ) else {
            return
        }

        guard sourceIndexPath != destinationIndexPath else {
            coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
            return
        }

        moveProvider(from: sourceIndexPath, to: destinationIndexPath)
        tableView.performBatchUpdates {
            tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
        }
        coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
    }
}
