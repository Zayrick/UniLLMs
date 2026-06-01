//
//  ToolsViewController.swift
//  UniLLMs
//
//  Displays tool-call settings, built-in tools, and configured MCP servers.
//  Created by Zayrick on 2026/5/15.
//

import UIKit

final class ToolsViewController: UITableViewController {
    private enum BuiltInToolRow {
        case tool(ToolDefinition)
        case memoryTools
    }

    private enum Section: Int, CaseIterable {
        case masterSwitch
        case builtInTools
        case mcpServers
    }

    private enum ReuseIdentifier {
        static let builtInToolCell = "BuiltInToolCell"
        static let serverCell = "MCPServerCell"
    }

    private let dependencies: AppDependencyContainer
    private var builtInToolRows: [BuiltInToolRow] = []
    private var servers: [MCPServerRecord] = []
    private var storeObservations: [NSObjectProtocol] = []
    private var localToolSettingsChangeNotificationsToIgnore = 0

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        self.dependencies = dependencies
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        dependencies = AppEnvironment.shared.dependencies
        super.init(coder: coder)
    }

    deinit {
        storeObservations.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Tools"
        configureAddButton()
        configureServerReordering()
        installStoreObservers()
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
            action: #selector(addMCPServer)
        )
    }

    private func configureServerReordering() {
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
    }

    private func installStoreObservers() {
        let toolSettingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsToolSettingsStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleToolSettingsStoreChange()
        }
        let mcpServerObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMCPServerStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadContent()
        }
        storeObservations = [toolSettingsObservation, mcpServerObservation]
    }

    private func reloadContent() {
        builtInToolRows = makeBuiltInToolRows()
        servers = dependencies.mcpServerManager.configuredServers()
        tableView.reloadData()
    }

    private func makeBuiltInToolRows() -> [BuiltInToolRow] {
        let tools = dependencies.toolSettingsManager.registeredBuiltInTools()
        var rows = tools
            .filter {
                !MemoryToolCatalog.containsTool(id: $0.id)
            }
            .map(BuiltInToolRow.tool)
        let hasMemoryTools = tools.contains {
            MemoryToolCatalog.containsTool(id: $0.id)
        }
        if hasMemoryTools {
            rows.append(.memoryTools)
        }
        return rows
    }

    private func handleToolSettingsStoreChange() {
        guard localToolSettingsChangeNotificationsToIgnore == 0 else {
            localToolSettingsChangeNotificationsToIgnore -= 1
            return
        }

        reloadContent()
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
        case .builtInTools:
            return builtInToolRows.count
        case .mcpServers:
            return servers.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }

        switch section {
        case .masterSwitch:
            return nil
        case .builtInTools:
            return "Built-In"
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
            return nil
        case .builtInTools:
            return builtInToolRows.isEmpty ? "No built-in tools are registered." : nil
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
        case .builtInTools:
            return builtInToolCell(for: indexPath)
        case .mcpServers:
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
        toggle.isOn = dependencies.toolSettingsManager.isToolsEnabled
        toggle.addTarget(self, action: #selector(toggleTools(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }

    private func builtInToolCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.builtInToolCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.builtInToolCell)

        switch builtInToolRows[indexPath.row] {
        case let .tool(tool):
            let isEnabled = dependencies.toolSettingsManager.isBuiltInToolEnabled(id: tool.id)
            configureBuiltInToolCellContent(
                cell,
                tool: tool,
                isEnabled: isEnabled
            )

            let toggle = UISwitch()
            toggle.isOn = isEnabled
            toggle.tag = indexPath.row
            toggle.addTarget(self, action: #selector(toggleBuiltInTool(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case .memoryTools:
            let enabledCount = memoryToolEnabledCount
            configureMemoryToolsCellContent(
                cell,
                enabledCount: enabledCount
            )

            let toggle = UISwitch()
            toggle.isOn = enabledCount > 0
            toggle.tag = indexPath.row
            toggle.addTarget(self, action: #selector(toggleBuiltInTool(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }

        cell.selectionStyle = .none
        return cell
    }

    private func configureBuiltInToolCellContent(
        _ cell: UITableViewCell,
        tool: ToolDefinition,
        isEnabled: Bool
    ) {
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = tool.presentationName
        contentConfiguration.secondaryText = tool.summary
        contentConfiguration.image = UIImage(systemName: tool.symbolName ?? "wrench.and.screwdriver")
        contentConfiguration.imageProperties.tintColor = isEnabled ? .systemGreen : .secondaryLabel
        cell.contentConfiguration = contentConfiguration
    }

    private func configureMemoryToolsCellContent(
        _ cell: UITableViewCell,
        enabledCount: Int
    ) {
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = "Memory Tools"
        contentConfiguration.secondaryText = "\(enabledCount) of \(MemoryToolCatalog.toolIDs.count) memory actions enabled. Manage details in Memories."
        contentConfiguration.image = UIImage(systemName: "brain.head.profile")
        contentConfiguration.imageProperties.tintColor = enabledCount > 0 ? .systemGreen : .secondaryLabel
        cell.contentConfiguration = contentConfiguration
    }

    private func serverCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.serverCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.serverCell)
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
        applyLocalToolSettingsChange(
            shouldIgnoreNotification: dependencies.toolSettingsManager.isToolsEnabled != sender.isOn
        ) {
            dependencies.toolSettingsManager.isToolsEnabled = sender.isOn
        }
    }

    @objc private func toggleBuiltInTool(_ sender: UISwitch) {
        guard builtInToolRows.indices.contains(sender.tag) else {
            return
        }

        switch builtInToolRows[sender.tag] {
        case let .tool(tool):
            applyLocalToolSettingsChange(
                shouldIgnoreNotification: dependencies.toolSettingsManager.isBuiltInToolEnabled(id: tool.id) != sender.isOn
            ) {
                dependencies.toolSettingsManager.setBuiltInTool(
                    id: tool.id,
                    isEnabled: sender.isOn
                )
            }
            if let cell = tableView.cellForRow(
                at: IndexPath(row: sender.tag, section: Section.builtInTools.rawValue)
            ) {
                configureBuiltInToolCellContent(
                    cell,
                    tool: tool,
                    isEnabled: sender.isOn
                )
            }
        case .memoryTools:
            applyLocalToolSettingsChange(
                shouldIgnoreNotification: memoryToolEnabledCount != (sender.isOn ? MemoryToolCatalog.toolIDs.count : 0)
            ) {
                dependencies.toolSettingsManager.setBuiltInTools(
                    ids: MemoryToolCatalog.toolIDs,
                    isEnabled: sender.isOn
                )
            }
            if let cell = tableView.cellForRow(
                at: IndexPath(row: sender.tag, section: Section.builtInTools.rawValue)
            ) {
                configureMemoryToolsCellContent(
                    cell,
                    enabledCount: sender.isOn ? MemoryToolCatalog.toolIDs.count : 0
                )
            }
        }
    }

    private func applyLocalToolSettingsChange(
        shouldIgnoreNotification: Bool,
        _ change: () -> Void
    ) {
        if shouldIgnoreNotification {
            localToolSettingsChangeNotificationsToIgnore += 1
        }

        change()
    }

    private func serverSubtitle(for server: MCPServerRecord) -> String? {
        let endpoint = server.configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            return nil
        }

        return endpoint
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

    private var memoryToolEnabledCount: Int {
        dependencies.toolSettingsManager.enabledBuiltInToolCount(ids: MemoryToolCatalog.toolIDs)
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
