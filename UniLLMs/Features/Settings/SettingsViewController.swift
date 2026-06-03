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
        case general
        case configuration

        var title: String {
            switch self {
            case .general:
                return String(localized: "settings.section.general")
            case .configuration:
                return String(localized: "settings.section.configuration")
            }
        }
    }

    private enum GeneralRow: Int, CaseIterable {
        case backgroundRuntime
    }

    private enum ConfigurationRow: Int, CaseIterable {
        case providers
        case memories
        case tools
        case permissions
        case systemPrompts

        var title: String {
            switch self {
            case .providers:
                return String(localized: .settingsRowProvidersTitle)
            case .memories:
                return String(localized: .settingsRowMemoriesTitle)
            case .tools:
                return String(localized: .settingsRowToolsTitle)
            case .permissions:
                return String(localized: "settings.row.permissions.title")
            case .systemPrompts:
                return String(localized: .settingsRowSystemPromptsTitle)
            }
        }

        var symbolName: String {
            switch self {
            case .providers:
                return "globe"
            case .memories:
                return "brain.head.profile"
            case .tools:
                return "hammer"
            case .permissions:
                return "key"
            case .systemPrompts:
                return "text.quote"
            }
        }

        var iconTintColor: UIColor {
            switch self {
            case .providers:
                return .systemBlue
            case .memories:
                return .systemTeal
            case .tools:
                return .systemGreen
            case .permissions:
                return .systemIndigo
            case .systemPrompts:
                return .systemPurple
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
        switch Section(rawValue: section) {
        case .general:
            return GeneralRow.allCases.count
        case .configuration:
            return ConfigurationRow.allCases.count
        case nil:
            return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .general:
            return generalCell(for: indexPath)
        case .configuration:
            return configurationCell(for: indexPath)
        case nil:
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
    }

    private func generalCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard GeneralRow(rawValue: indexPath.row) == .backgroundRuntime else {
            return cell
        }

        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = String(localized: "settings.background_runtime.title")
        contentConfiguration.image = UIImage(systemName: "arrow.triangle.2.circlepath.circle")
        contentConfiguration.imageProperties.tintColor = .systemOrange
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

    private func configurationCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard let row = ConfigurationRow(rawValue: indexPath.row) else {
            return cell
        }

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
        guard Section(rawValue: indexPath.section) == .configuration,
              let row = ConfigurationRow(rawValue: indexPath.row) else {
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
                MemoriesViewController(dependencies: dependencies),
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
        case .systemPrompts:
            navigationController?.pushViewController(
                SystemPromptsViewController(dependencies: dependencies),
                animated: true
            )
        }
    }
}
