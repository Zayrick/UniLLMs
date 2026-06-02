//
//  MemoryListViewController.swift
//  UniLLMs
//
//  Displays saved memories for review and editing.
//

import UIKit

final class MemoryListViewController: UITableViewController {
    private enum ReuseIdentifier {
        static let memoryCell = "MemoryCell"
    }

    private let dependencies: AppDependencyContainer
    private let searchController = UISearchController(searchResultsController: nil)
    private var memories: [MemoryRecord] = []
    private var visibleMemories: [MemoryRecord] = []
    private var storeObservation: NSObjectProtocol?
    private var reloadTask: Task<Void, Never>?

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        self.dependencies = dependencies
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        dependencies = AppEnvironment.shared.dependencies
        super.init(coder: coder)
    }

    deinit {
        reloadTask?.cancel()
        if let storeObservation {
            NotificationCenter.default.removeObserver(storeObservation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: .memoriesSavedMemories)
        configureAddButton()
        configureSearch()
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
            action: #selector(addMemory)
        )
    }

    private func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: .memoriesSearchSavedMemories)
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func installStoreObserver() {
        storeObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMemoryStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadContent()
        }
    }

    private func reloadContent() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let memories = try await self.dependencies.memoryManager.savedMemories(scope: .user)
                guard !Task.isCancelled else {
                    return
                }

                self.memories = memories
                self.applySearchFilter()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self.memories = []
                self.visibleMemories = []
                self.tableView.reloadData()
                self.setNeedsUpdateContentUnavailableConfiguration()
            }
        }
    }

    @objc private func addMemory() {
        navigationController?.pushViewController(
            MemoryEditorViewController(
                memory: dependencies.memoryManager.makeMemoryDraft(),
                dependencies: dependencies,
                isNewMemory: true
            ),
            animated: true
        )
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleMemories.count
    }

    override func updateContentUnavailableConfiguration(
        using state: UIContentUnavailableConfigurationState
    ) {
        guard visibleMemories.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }

        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "brain.head.profile")
        if memories.isEmpty {
            configuration.text = String(localized: .memoriesEmptyNoSavedTitle)
            configuration.secondaryText = String(localized: .memoriesEmptyNoSavedDetail)
            configuration.button = addMemoryButtonConfiguration()
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
                self?.addMemory()
            }
        } else {
            configuration.text = String(localized: .memoriesEmptyNoMatchingTitle)
            configuration.secondaryText = String(localized: .memoriesEmptyNoMatchingDetail)
        }
        contentUnavailableConfiguration = configuration
    }

    private func addMemoryButtonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: .memoriesAddMemory)
        configuration.image = UIImage(systemName: "plus")
        configuration.imagePadding = 6
        return configuration
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        memoryCell(for: indexPath)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard visibleMemories.indices.contains(indexPath.row) else {
            return
        }

        navigationController?.pushViewController(
            MemoryEditorViewController(
                memory: visibleMemories[indexPath.row],
                dependencies: dependencies
            ),
            animated: true
        )
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard visibleMemories.indices.contains(indexPath.row) else {
            return nil
        }

        let memoryID = visibleMemories[indexPath.row].id
        let deleteAction = UIContextualAction(style: .destructive, title: String(localized: .generalDelete)) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }

            Task { @MainActor in
                do {
                    try await self.dependencies.memoryManager.deleteMemory(id: memoryID)
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func memoryCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.memoryCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.memoryCell)
        let memory = visibleMemories[indexPath.row]
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = displayText(for: memory)
        contentConfiguration.secondaryText = String(localized: .generalUpdatedFormat(memory.updatedAt.formatted(date: .abbreviated, time: .shortened)))
        contentConfiguration.secondaryTextProperties.numberOfLines = 1
        contentConfiguration.image = UIImage(systemName: "brain.head.profile")
        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func applySearchFilter() {
        let query = searchController.searchBar.text ?? ""
        visibleMemories = MemoryTextSearch.filtered(memories, matching: query)
        tableView.reloadData()
        setNeedsUpdateContentUnavailableConfiguration()
    }

    private func displayText(for memory: MemoryRecord) -> String {
        let text = memory.text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? String(localized: .memoriesUntitledMemory) : text
    }
}

extension MemoryListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applySearchFilter()
    }
}
