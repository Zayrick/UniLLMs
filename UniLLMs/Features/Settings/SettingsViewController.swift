//
//  SettingsViewController.swift
//  UniLLMs
//
//  Displays settings entry points.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class SettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case modelAndConversation
        case capabilities
        case appAndSystem

        var title: String {
            switch self {
            case .modelAndConversation:
                return String(localized: "settings.section.model_and_conversation")
            case .capabilities:
                return String(localized: "settings.section.capabilities")
            case .appAndSystem:
                return String(localized: "settings.section.app_and_system")
            }
        }

        var rows: [Row] {
            switch self {
            case .modelAndConversation:
                return [.providers, .systemPrompts]
            case .capabilities:
                return [.memories, .tools]
            case .appAndSystem:
                return [.backgroundRuntime, .permissions, .about]
            }
        }
    }

    private enum Row {
        case providers
        case systemPrompts
        case memories
        case tools
        case backgroundRuntime
        case permissions
        case about

        var title: String {
            switch self {
            case .providers:
                return String(localized: .settingsRowProvidersTitle)
            case .systemPrompts:
                return String(localized: .settingsRowSystemPromptsTitle)
            case .memories:
                return String(localized: .settingsRowMemoriesTitle)
            case .tools:
                return String(localized: .settingsRowToolsTitle)
            case .backgroundRuntime:
                return String(localized: "settings.background_runtime.title")
            case .permissions:
                return String(localized: "settings.row.permissions.title")
            case .about:
                return String(localized: "settings.row.about.title")
            }
        }

        var symbolName: String {
            switch self {
            case .providers:
                return "globe"
            case .systemPrompts:
                return "text.quote"
            case .memories:
                return "brain.head.profile"
            case .tools:
                return "hammer"
            case .backgroundRuntime:
                return "arrow.triangle.2.circlepath.circle"
            case .permissions:
                return "key"
            case .about:
                return "info.circle"
            }
        }

        var iconTintColor: UIColor {
            switch self {
            case .providers:
                return .systemBlue
            case .systemPrompts:
                return .systemPurple
            case .memories:
                return .systemTeal
            case .tools:
                return .systemGreen
            case .backgroundRuntime:
                return .systemOrange
            case .permissions:
                return .systemIndigo
            case .about:
                return .systemGray
            }
        }
    }

    private let dependencies: AppDependencyContainer

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

        title = String(localized: .generalSettings)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func backgroundRuntimeSwitchChanged(_ sender: UISwitch) {
        dependencies.appSettingsStore.isBackgroundRuntimeEnabled = sender.isOn
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Section(rawValue: section)?.rows.count ?? 0
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let row = row(for: indexPath) else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }

        switch row {
        case .backgroundRuntime:
            return backgroundRuntimeCell(for: row)
        case .providers, .systemPrompts, .memories, .tools, .permissions, .about:
            return navigationCell(for: row)
        }
    }

    private func row(for indexPath: IndexPath) -> Row? {
        guard let section = Section(rawValue: indexPath.section),
              section.rows.indices.contains(indexPath.row) else {
            return nil
        }

        return section.rows[indexPath.row]
    }

    private func backgroundRuntimeCell(for row: Row) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = row.title
        contentConfiguration.image = UIImage(systemName: row.symbolName)
        contentConfiguration.imageProperties.tintColor = row.iconTintColor
        cell.contentConfiguration = contentConfiguration

        let backgroundRuntimeSwitch = UISwitch()
        backgroundRuntimeSwitch.isOn = dependencies.appSettingsStore.isBackgroundRuntimeEnabled
        backgroundRuntimeSwitch.addTarget(
            self,
            action: #selector(backgroundRuntimeSwitchChanged(_:)),
            for: .valueChanged
        )
        backgroundRuntimeSwitch.accessibilityLabel = contentConfiguration.text
        cell.accessoryView = backgroundRuntimeSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func navigationCell(for row: Row) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = row.title
        contentConfiguration.image = UIImage(systemName: row.symbolName)
        contentConfiguration.imageProperties.tintColor = row.iconTintColor
        cell.contentConfiguration = contentConfiguration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = row(for: indexPath) else {
            return
        }

        switch row {
        case .providers:
            navigationController?.pushViewController(
                LLMsProviderViewController(dependencies: dependencies),
                animated: true
            )
        case .memories:
            navigationController?.pushViewController(
                MemoryListViewController(dependencies: dependencies),
                animated: true
            )
        case .tools:
            navigationController?.pushViewController(
                ToolsViewController(dependencies: dependencies),
                animated: true
            )
        case .permissions:
            navigationController?.pushViewController(
                PermissionsViewController(),
                animated: true
            )
        case .about:
            navigationController?.pushViewController(
                AboutViewController(),
                animated: true
            )
        case .systemPrompts:
            navigationController?.pushViewController(
                SystemPromptSettingsViewController(dependencies: dependencies),
                animated: true
            )
        case .backgroundRuntime:
            return
        }
    }
}
