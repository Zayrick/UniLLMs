//
//  AboutViewController.swift
//  UniLLMs
//
//  Displays project, contact, open-source, and policy information.
//

import UIKit

final class AboutViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case project
        case contact
        case legal

        var title: String {
            switch self {
            case .project:
                return String(localized: "about.section.project")
            case .contact:
                return String(localized: "about.section.contact")
            case .legal:
                return String(localized: "about.section.legal")
            }
        }

        var rows: [Row] {
            switch self {
            case .project:
                return [.summary]
            case .contact:
                return [.email, .openSource]
            case .legal:
                return [.privacyPolicy, .license]
            }
        }
    }

    private enum Row {
        case summary
        case email
        case openSource
        case privacyPolicy
        case license

        var title: String {
            switch self {
            case .summary:
                return String(localized: "about.summary.title")
            case .email:
                return String(localized: "about.email.title")
            case .openSource:
                return String(localized: "about.open_source.title")
            case .privacyPolicy:
                return String(localized: "about.privacy_policy.title")
            case .license:
                return String(localized: "about.license.title")
            }
        }

        var detail: String {
            switch self {
            case .summary:
                return String(localized: "about.summary.detail")
            case .email:
                return Constants.contactEmail
            case .openSource:
                return Constants.sourceRepositoryDisplay
            case .privacyPolicy:
                return String(localized: "about.privacy_policy.detail")
            case .license:
                return String(localized: "about.license.detail")
            }
        }

        var symbolName: String {
            switch self {
            case .summary:
                return "app"
            case .email:
                return "envelope"
            case .openSource:
                return "chevron.left.forwardslash.chevron.right"
            case .privacyPolicy:
                return "hand.raised"
            case .license:
                return "doc.text"
            }
        }

        var iconTintColor: UIColor {
            switch self {
            case .summary:
                return .systemBlue
            case .email:
                return .systemGreen
            case .openSource:
                return .systemPurple
            case .privacyPolicy:
                return .systemIndigo
            case .license:
                return .systemGray
            }
        }

        var accessoryType: UITableViewCell.AccessoryType {
            switch self {
            case .summary:
                return .none
            case .email, .openSource, .privacyPolicy, .license:
                return .disclosureIndicator
            }
        }

        var selectionStyle: UITableViewCell.SelectionStyle {
            switch self {
            case .summary:
                return .none
            case .email, .openSource, .privacyPolicy, .license:
                return .default
            }
        }
    }

    private enum Constants {
        static let contactEmail = "tvefxt@gmail.com"
        static let sourceRepositoryDisplay = "Zayrick/UniLLMs"
        static let contactEmailURL = URL(string: "mailto:tvefxt@gmail.com")
        static let sourceRepositoryURL = URL(string: "https://github.com/Zayrick/UniLLMs")
        static let licenseURL = URL(string: "https://github.com/Zayrick/UniLLMs/blob/main/LICENSE")
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: "about.title")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68.0
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

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.secondaryText = row.detail
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: row.symbolName)
        content.imageProperties.tintColor = row.iconTintColor
        cell.contentConfiguration = content
        cell.accessoryType = row.accessoryType
        cell.selectionStyle = row.selectionStyle
        cell.accessibilityLabel = "\(row.title), \(row.detail)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = row(for: indexPath) else {
            return
        }

        switch row {
        case .summary:
            return
        case .email:
            open(Constants.contactEmailURL)
        case .openSource:
            open(Constants.sourceRepositoryURL)
        case .privacyPolicy:
            navigationController?.pushViewController(PrivacyPolicyViewController(), animated: true)
        case .license:
            open(Constants.licenseURL)
        }
    }

    private func row(for indexPath: IndexPath) -> Row? {
        guard let section = Section(rawValue: indexPath.section),
              section.rows.indices.contains(indexPath.row) else {
            return nil
        }

        return section.rows[indexPath.row]
    }

    private func open(_ url: URL?) {
        guard let url else {
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
