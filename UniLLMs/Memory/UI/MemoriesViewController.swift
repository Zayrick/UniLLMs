//
//  MemoriesViewController.swift
//  UniLLMs
//
//  Shows memory settings and saved-memory actions.
//

import UIKit

final class MemoriesViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case assistantAccess
        case savedMemories
        case clear

        var headerTitle: String? {
            switch self {
            case .assistantAccess:
                return String(localized: .memoriesSectionAssistantAccess)
            case .savedMemories:
                return String(localized: .memoriesSavedMemories)
            case .clear:
                return nil
            }
        }

        var footerTitle: String? {
            switch self {
            case .assistantAccess:
                return String(localized: .memoriesFooterRequiresTools)
            case .savedMemories:
                return nil
            case .clear:
                return nil
            }
        }
    }

    private enum SavedMemoryRow: Int, CaseIterable {
        case list
    }

    private enum ClearRow: Int, CaseIterable {
        case clearAll
    }

    private enum ReuseIdentifier {
        static let settingCell = "MemorySettingCell"
        static let toolCell = "MemoryToolSettingCell"
        static let actionCell = "MemoryActionCell"
    }

    private let dependencies: AppDependencyContainer
    private var memoryToolItems: [MemoryToolUserFacingItem] = []
    private var memoryCount = 0
    private var storeObservations: [NSObjectProtocol] = []
    private var memoryCountTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        self.dependencies = dependencies
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        dependencies = AppEnvironment.shared.dependencies
        super.init(coder: coder)
    }

    deinit {
        memoryCountTask?.cancel()
        clearTask?.cancel()
        storeObservations.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: .settingsRowMemoriesTitle)
        installStoreObservers()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadContent()
    }

    private func installStoreObservers() {
        let toolSettingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsToolSettingsStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleToolSettingsStoreChange()
        }
        let memoryObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMemoryStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadMemoryCount()
        }
        storeObservations = [
            toolSettingsObservation,
            memoryObservation
        ]
    }

    private func reloadContent() {
        memoryToolItems = registeredMemoryToolItems()
        reloadMemoryCount()
        tableView.reloadData()
    }

    private func registeredMemoryToolItems() -> [MemoryToolUserFacingItem] {
        let registeredToolIDs = Set(dependencies.toolSettingsManager.registeredBuiltInTools().map(\.id))
        return MemoryToolCatalog.userFacingItems.filter {
            registeredToolIDs.contains($0.id)
        }
    }

    private func reloadMemoryCount() {
        memoryCountTask?.cancel()
        memoryCountTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let count = try await self.dependencies.memoryManager.savedMemories(scope: .user).count
                guard !Task.isCancelled else {
                    return
                }

                self.memoryCount = count
                self.tableView.reloadSections(
                    IndexSet([
                        Section.savedMemories.rawValue,
                        Section.clear.rawValue
                    ]),
                    with: .automatic
                )
            } catch {
                return
            }
        }
    }

    private func handleToolSettingsStoreChange() {
        let updatedMemoryToolItems = registeredMemoryToolItems()
        guard updatedMemoryToolItems.map(\.id) == memoryToolItems.map(\.id) else {
            memoryToolItems = updatedMemoryToolItems
            tableView.reloadSections(IndexSet(integer: Section.assistantAccess.rawValue), with: .none)
            return
        }

        memoryToolItems = updatedMemoryToolItems
        updateVisibleMemoryToolCells()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .assistantAccess:
            return memoryToolItems.count
        case .savedMemories:
            return SavedMemoryRow.allCases.count
        case .clear:
            return ClearRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.headerTitle
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section)?.footerTitle
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .assistantAccess:
            return memoryToolCell(for: indexPath)
        case .savedMemories:
            return savedMemoryCell()
        case .clear:
            return clearAllCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch section {
        case .assistantAccess:
            return
        case .savedMemories:
            navigationController?.pushViewController(
                MemoryListViewController(dependencies: dependencies),
                animated: true
            )
        case .clear:
            guard memoryCount > 0 else {
                return
            }

            presentClearAllConfirmation()
        }
    }

    private func memoryToolCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.toolCell)
            ?? UITableViewCell(style: .default, reuseIdentifier: ReuseIdentifier.toolCell)
        let item = memoryToolItems[indexPath.row]
        let isEnabled = dependencies.toolSettingsManager.isBuiltInToolEnabled(id: item.id)
        configureMemoryToolCellContent(
            cell,
            item: item,
            isEnabled: isEnabled
        )

        let toggle = UISwitch()
        toggle.isOn = isEnabled
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleMemoryTool(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.accessoryType = .none
        cell.selectionStyle = .none
        return cell
    }

    private func configureMemoryToolCellContent(
        _ cell: UITableViewCell,
        item: MemoryToolUserFacingItem,
        isEnabled: Bool
    ) {
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = item.title
        contentConfiguration.image = UIImage(systemName: item.symbolName)
        contentConfiguration.imageProperties.tintColor = isEnabled ? .systemGreen : .secondaryLabel
        cell.contentConfiguration = contentConfiguration
    }

    private func savedMemoryCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.actionCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.actionCell)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = String(localized: .memoriesSavedMemories)
        contentConfiguration.secondaryText = memoryCountDescription
        contentConfiguration.image = UIImage(systemName: "brain.head.profile")
        contentConfiguration.imageProperties.tintColor = .systemTeal
        cell.contentConfiguration = contentConfiguration
        cell.accessoryView = nil
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    private func clearAllCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = String(localized: .memoriesClearAll)
        contentConfiguration.image = UIImage(systemName: "trash")
        contentConfiguration.textProperties.color = memoryCount > 0 ? .systemRed : .secondaryLabel
        contentConfiguration.imageProperties.tintColor = memoryCount > 0 ? .systemRed : .secondaryLabel
        cell.contentConfiguration = contentConfiguration
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = memoryCount > 0 ? .default : .none
        return cell
    }

    @objc private func toggleMemoryTool(_ sender: UISwitch) {
        guard memoryToolItems.indices.contains(sender.tag) else {
            return
        }

        let item = memoryToolItems[sender.tag]
        dependencies.toolSettingsManager.setBuiltInTool(id: item.id, isEnabled: sender.isOn)
        let indexPath = IndexPath(row: sender.tag, section: Section.assistantAccess.rawValue)
        if let cell = tableView.cellForRow(at: indexPath) {
            configureMemoryToolCellContent(
                cell,
                item: item,
                isEnabled: sender.isOn
            )
        }
    }

    private func presentClearAllConfirmation() {
        let message = memoryCount == 1
            ? String(localized: .memoriesClearAllConfirmationOneMessage)
            : String(localized: .memoriesClearAllConfirmationCountMessageFormat(memoryCount))
        let alertController = UIAlertController(
            title: String(localized: .memoriesClearAllConfirmationTitle),
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: String(localized: .generalCancel), style: .cancel))
        alertController.addAction(
            UIAlertAction(title: String(localized: .memoriesClearMemories), style: .destructive) { [weak self] _ in
                self?.clearAllMemories()
            }
        )
        present(alertController, animated: true)
    }

    private func clearAllMemories() {
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await self.dependencies.memoryManager.deleteAllMemories(scope: .user)
                self.memoryCount = 0
                self.tableView.reloadSections(
                    IndexSet([
                        Section.savedMemories.rawValue,
                        Section.clear.rawValue
                    ]),
                    with: .automatic
                )
            } catch {
                self.reloadMemoryCount()
            }
        }
    }

    private func updateVisibleMemoryToolCells() {
        for (row, item) in memoryToolItems.enumerated() {
            let indexPath = IndexPath(row: row, section: Section.assistantAccess.rawValue)
            guard let cell = tableView.cellForRow(at: indexPath) else {
                continue
            }

            let isEnabled = dependencies.toolSettingsManager.isBuiltInToolEnabled(id: item.id)
            configureMemoryToolCellContent(
                cell,
                item: item,
                isEnabled: isEnabled
            )
            if let toggle = cell.accessoryView as? UISwitch,
               toggle.isOn != isEnabled {
                toggle.setOn(isEnabled, animated: false)
            }
        }
    }

    private var memoryCountDescription: String {
        switch memoryCount {
        case 0:
            return String(localized: .memoriesCountNone)
        case 1:
            return String(localized: .memoriesCountOne)
        default:
            return String(localized: .memoriesCountFormat(memoryCount))
        }
    }
}
