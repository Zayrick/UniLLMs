//
//  SettingsViewController.swift
//  UniLLMs
//
//  Displays settings entry points.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class SettingsViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case providers
        case tools
        case systemPrompts

        var title: String {
            switch self {
            case .providers:
                return "LLM Providers"
            case .tools:
                return "Tools"
            case .systemPrompts:
                return "System Prompts"
            }
        }

        var symbolName: String {
            switch self {
            case .providers:
                return "globe"
            case .tools:
                return "hammer"
            case .systemPrompts:
                return "text.quote"
            }
        }

        var iconTintColor: UIColor {
            switch self {
            case .providers:
                return .systemBlue
            case .tools:
                return .systemGreen
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

        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard let row = Row(rawValue: indexPath.row) else {
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
        guard let row = Row(rawValue: indexPath.row) else {
            return
        }

        switch row {
        case .providers:
            navigationController?.pushViewController(
                LLMsProviderViewController(dependencies: dependencies),
                animated: true
            )
        case .tools:
            navigationController?.pushViewController(
                ToolsViewController(dependencies: dependencies),
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
