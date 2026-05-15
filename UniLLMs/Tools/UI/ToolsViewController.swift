//
//  ToolsViewController.swift
//  UniLLMs
//
//  Displays tool-call settings and configured MCP servers.
//  Created by Codex on 2026/5/15.
//

import UIKit

final class ToolsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case masterSwitch
        case mcpServers
    }

    private let dependencies: AppDependencyContainer
    private var servers: [MCPServerRecord] = []
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

        title = "Tools"
        configureAddButton()
        configureServerReordering()
        installStoreObserver()
        reloadServers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadServers()
    }

    private func configureAddButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addMCPServer)
        )
    }

    private func configureServerReordering() {
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
    }

    private func installStoreObserver() {
        storeObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMCPServerStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadServers()
        }
    }

    private func reloadServers() {
        let loadedServers = dependencies.mcpServerManager.configuredServers()
        guard loadedServers != servers else {
            return
        }

        servers = loadedServers
        tableView.reloadSections(
            IndexSet(integer: Section.mcpServers.rawValue),
            with: .automatic
        )
    }

    @objc private func addMCPServer() {
        let server = dependencies.mcpServerManager.makeServerDraft()
        navigationController?.pushViewController(
            MCPServerConfigurationViewController(
                server: server,
                dependencies: dependencies,
                isNewServer: true
            ),
            animated: true
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .masterSwitch:
            return 1
        case .mcpServers:
            return max(servers.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }

        switch section {
        case .masterSwitch:
            return nil
        case .mcpServers:
            return "MCP"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }

        switch section {
        case .masterSwitch:
            return "When tools are enabled and at least one MCP server exposes tools, compatible chat requests include tool definitions and execute model-requested tool calls."
        case .mcpServers:
            return servers.isEmpty ? "Add a Streamable HTTP MCP server to expose tools to the selected model." : nil
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
        case .masterSwitch:
            return masterSwitchCell()
        case .mcpServers:
            guard !servers.isEmpty else {
                return emptyServerCell()
            }
            return serverCell(for: indexPath)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section),
              section == .mcpServers,
              servers.indices.contains(indexPath.row) else {
            return
        }

        navigationController?.pushViewController(
            MCPServerConfigurationViewController(
                server: servers[indexPath.row],
                dependencies: dependencies
            ),
            animated: true
        )
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Section.mcpServers.rawValue && servers.count > 1
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        moveServer(from: sourceIndexPath, to: destinationIndexPath)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard !servers.isEmpty else {
            return proposedDestinationIndexPath
        }

        let row = min(max(proposedDestinationIndexPath.row, 0), servers.count - 1)
        return IndexPath(row: row, section: Section.mcpServers.rawValue)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == Section.mcpServers.rawValue,
              servers.indices.contains(indexPath.row) else {
            return nil
        }

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self,
                  servers.indices.contains(indexPath.row) else {
                completion(false)
                return
            }

            let server = servers[indexPath.row]
            dependencies.mcpServerManager.deleteServer(id: server.id)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func masterSwitchCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = "Enable Tools"
        contentConfiguration.secondaryText = "Allow tools in chat requests"
        contentConfiguration.image = UIImage(systemName: "hammer")
        cell.contentConfiguration = contentConfiguration

        let toggle = UISwitch()
        toggle.isOn = dependencies.mcpServerManager.isToolsEnabled
        toggle.addTarget(self, action: #selector(toggleTools(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }

    private func emptyServerCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = "No MCP Servers"
        contentConfiguration.secondaryText = "Tap + to add one"
        contentConfiguration.image = UIImage(systemName: "server.rack")
        contentConfiguration.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.selectionStyle = .none
        return cell
    }

    private func serverCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let server = servers[indexPath.row]
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = server.displayName
        contentConfiguration.secondaryText = serverSubtitle(for: server)
        contentConfiguration.image = UIImage(systemName: "server.rack")
        contentConfiguration.imageProperties.tintColor = server.configuration.isEnabled ? .systemGreen : .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = .disclosureIndicator
        cell.showsReorderControl = servers.count > 1
        return cell
    }

    @objc private func toggleTools(_ sender: UISwitch) {
        dependencies.mcpServerManager.isToolsEnabled = sender.isOn
    }

    private func serverSubtitle(for server: MCPServerRecord) -> String {
        let endpoint = server.configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = server.configuration.isEnabled ? "Enabled" : "Disabled"
        guard !endpoint.isEmpty else {
            return status
        }

        return "\(status) • \(endpoint)"
    }

    @discardableResult
    private func moveServer(from sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) -> Bool {
        guard sourceIndexPath.section == Section.mcpServers.rawValue,
              destinationIndexPath.section == Section.mcpServers.rawValue,
              servers.indices.contains(sourceIndexPath.row),
              servers.indices.contains(destinationIndexPath.row),
              sourceIndexPath != destinationIndexPath else {
            return false
        }

        let server = servers.remove(at: sourceIndexPath.row)
        servers.insert(server, at: destinationIndexPath.row)
        dependencies.mcpServerManager.moveServer(
            from: sourceIndexPath.row,
            to: destinationIndexPath.row
        )
        return true
    }

    private func dragItem(for server: MCPServerRecord) -> UIDragItem {
        let itemProvider = NSItemProvider(object: server.id.uuidString as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = server.id
        return dragItem
    }

    private func serverMoveDestinationIndexPath(from proposedIndexPath: IndexPath?) -> IndexPath? {
        guard !servers.isEmpty else {
            return nil
        }

        let proposedRow = proposedIndexPath?.row ?? servers.count - 1
        let row = min(max(proposedRow, 0), servers.count - 1)
        return IndexPath(row: row, section: Section.mcpServers.rawValue)
    }

    private func containsServerDragItem(_ session: UIDropSession) -> Bool {
        session.localDragSession?.items.contains { item in
            item.localObject is UUID
        } == true
    }
}

extension ToolsViewController: UITableViewDragDelegate {
    func tableView(
        _ tableView: UITableView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard indexPath.section == Section.mcpServers.rawValue,
              servers.count > 1,
              servers.indices.contains(indexPath.row) else {
            return []
        }

        return [dragItem(for: servers[indexPath.row])]
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

extension ToolsViewController: UITableViewDropDelegate {
    func tableView(
        _ tableView: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UITableViewDropProposal {
        guard servers.count > 1,
              containsServerDragItem(session) else {
            return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let item = coordinator.items.first(where: { $0.dragItem.localObject is UUID }),
              let sourceIndexPath = item.sourceIndexPath,
              let serverID = item.dragItem.localObject as? UUID,
              sourceIndexPath.section == Section.mcpServers.rawValue,
              servers.indices.contains(sourceIndexPath.row),
              servers[sourceIndexPath.row].id == serverID,
              let destinationIndexPath = serverMoveDestinationIndexPath(
                from: coordinator.destinationIndexPath
              ) else {
            return
        }

        guard sourceIndexPath != destinationIndexPath else {
            coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
            return
        }

        moveServer(from: sourceIndexPath, to: destinationIndexPath)
        tableView.performBatchUpdates {
            tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
        }
        coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
    }
}
