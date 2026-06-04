//
//  AboutViewController.swift
//  UniLLMs
//
//  Displays app, contact, open-source, and policy information.
//

import UIKit

final class AboutViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case contact
        case legal

        var title: String {
            switch self {
            case .contact:
                return String(localized: "about.section.contact")
            case .legal:
                return String(localized: "about.section.legal")
            }
        }

        var rows: [Row] {
            switch self {
            case .contact:
                return [.email, .openSource]
            case .legal:
                return [.privacyPolicy, .license]
            }
        }
    }

    private enum Row {
        case email
        case openSource
        case privacyPolicy
        case license

        var title: String {
            switch self {
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
            case .email, .openSource, .privacyPolicy, .license:
                return .disclosureIndicator
            }
        }

        var selectionStyle: UITableViewCell.SelectionStyle {
            switch self {
            case .email, .openSource, .privacyPolicy, .license:
                return .default
            }
        }
    }

    private enum Constants {
        static let contactEmail = "tvefxt@gmail.com"
        static let headerImageName = "AboutAppIcon"
        static let sourceRepositoryDisplay = "Zayrick/UniLLMs"
        static let contactEmailURL = URL(string: "mailto:tvefxt@gmail.com")
        static let sourceRepositoryURL = URL(string: "https://github.com/Zayrick/UniLLMs")
        static let licenseURL = URL(string: "https://github.com/Zayrick/UniLLMs/blob/main/LICENSE")
    }

    private enum Metrics {
        static let navigationTitleRevealDistance = 32.0
    }

    private let navigationTitle = String(localized: "about.title")
    private var isNavigationTitleVisible = false

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = nil
        navigationItem.largeTitleDisplayMode = .never
        configureHeaderView()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68.0
        updateNavigationTitleVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.prefersLargeTitles = false
        updateNavigationTitleVisibility()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateHeaderViewSize()
        updateNavigationTitleVisibility()
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

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationTitleVisibility()
    }

    private func configureHeaderView() {
        tableView.tableHeaderView = AboutHeaderView(
            image: UIImage(named: Constants.headerImageName),
            name: String(localized: "about.summary.title"),
            summary: String(localized: "about.summary.detail")
        )
    }

    private func updateHeaderViewSize() {
        guard let headerView = tableView.tableHeaderView,
              tableView.bounds.width > 0 else {
            return
        }

        let fittingSize = CGSize(
            width: tableView.bounds.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        let height = headerView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard abs(headerView.frame.width - tableView.bounds.width) > 0.5 ||
              abs(headerView.frame.height - height) > 0.5 else {
            return
        }

        var frame = headerView.frame
        frame.size.width = tableView.bounds.width
        frame.size.height = height
        headerView.frame = frame
        tableView.tableHeaderView = headerView
    }

    private func updateNavigationTitleVisibility() {
        let headerBottomY = tableView.tableHeaderView?.frame.maxY ?? 0.0
        let revealOffsetY = max(0.0, headerBottomY - Metrics.navigationTitleRevealDistance)
        let adjustedOffsetY = tableView.contentOffset.y + tableView.adjustedContentInset.top
        setNavigationTitleVisible(adjustedOffsetY >= revealOffsetY)
    }

    private func setNavigationTitleVisible(_ isVisible: Bool) {
        guard isNavigationTitleVisible != isVisible else {
            return
        }

        isNavigationTitleVisible = isVisible
        navigationItem.title = isVisible ? navigationTitle : nil
    }

    private func open(_ url: URL?) {
        guard let url else {
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

private final class AboutHeaderView: UIView {
    private enum Metrics {
        static let iconSize = 92.0
        static let topInset = 30.0
        static let horizontalInset = 24.0
        static let bottomInset = 24.0
        static let iconNameSpacing = 14.0
        static let nameSummarySpacing = 8.0
    }

    init(image: UIImage?, name: String, summary: String) {
        super.init(frame: .zero)

        configureLayout(image: image, name: name, summary: summary)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func configureLayout(image: UIImage?, name: String, summary: String) {
        layoutMargins = UIEdgeInsets(
            top: Metrics.topInset,
            left: Metrics.horizontalInset,
            bottom: Metrics.bottomInset,
            right: Metrics.horizontalInset
        )

        let iconImageView = UIImageView(image: image)
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.isAccessibilityElement = false

        let iconContainerView = UIView()
        iconContainerView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.addSubview(iconImageView)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24.0, weight: .semibold)
        )
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textAlignment = .center
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 0
        nameLabel.accessibilityTraits.insert(.header)

        let summaryLabel = UILabel()
        summaryLabel.text = summary
        summaryLabel.font = .preferredFont(forTextStyle: .subheadline)
        summaryLabel.adjustsFontForContentSizeCategory = true
        summaryLabel.textAlignment = .center
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [
            iconContainerView,
            nameLabel,
            summaryLabel
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setCustomSpacing(Metrics.iconNameSpacing, after: iconContainerView)
        stackView.setCustomSpacing(Metrics.nameSummarySpacing, after: nameLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: iconContainerView.topAnchor),
            iconImageView.bottomAnchor.constraint(equalTo: iconContainerView.bottomAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])
    }
}
