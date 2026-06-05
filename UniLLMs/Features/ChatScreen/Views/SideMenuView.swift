//
//  SideMenuView.swift
//  UniLLMs
//
//  Displays chat history, search, and settings in the side menu.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class SideMenuView: UIView {
    private final class GroundedTableView: UITableView {
        @objc var allowsHeaderViewsToFloat: Bool {
            false
        }

        @objc var allowsFooterViewsToFloat: Bool {
            false
        }
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 16.0
        static let titleTopSpacing: CGFloat = 18.0
        static let historyTopSpacing: CGFloat = 18.0
        static let historyBottomSpacing: CGFloat = 12.0
        static let historyCellHeight: CGFloat = 48.0
        static let historyHeaderHeight: CGFloat = 30.0
        static let keyboardBottomSpacing: CGFloat = 8.0
        static let controlHeight: CGFloat = 48.0
        static let controlSpacing: CGFloat = 10.0
        static let searchHorizontalInset: CGFloat = 16.0
        static let searchIconSize: CGFloat = 17.0
        static let settingsButtonSize: CGFloat = 48.0
        static let settingsIconSize: CGFloat = 20.0
    }

    var onSessionSelected: ((ChatSession) -> Void)?
    var onSessionDeleted: ((ChatSession) -> Void)?

    private let titleLabel = UILabel()
    private let visibleHistoryLayoutGuide = UILayoutGuide()
    private let historyTableView = GroundedTableView(frame: .zero, style: .plain)
    private let emptyHistoryLabel = UILabel()
    private let bottomGlassContainerView = UIVisualEffectView(effect: SideMenuView.makeContainerEffect())
    private let bottomStackView = UIStackView()
    private let searchGlassView = UIVisualEffectView(effect: SideMenuView.makeGlassEffect())
    private let searchRowView = UIStackView()
    private let searchIconView = UIImageView()
    private let searchTextField = UITextField()
    private let settingsGlassView = UIVisualEffectView(effect: SideMenuView.makeGlassEffect())
    private let settingsButton = UIButton(type: .system)
    private var allSessions: [ChatSession] = []
    private var historySections: [HistorySection] = []
    private var selectedSessionID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func resignSearchFocus() {
        searchTextField.resignFirstResponder()
    }

    func addSettingsTarget(_ target: Any?, action: Selector) {
        settingsButton.addTarget(target, action: action, for: .touchUpInside)
    }

    func reloadHistory(
        sessions: [ChatSession],
        selectedSessionID: UUID?
    ) {
        allSessions = sessions.sorted(by: Self.sortSessionsByLastSentDate)
        self.selectedSessionID = selectedSessionID
        applyHistoryFilter()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureTitle()
        configureBottomBar()
        configureHistoryList()
        configureSearchField()
        configureSettingsButton()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        updateHistoryContentInsets()
    }

    private func configureTitle() {
        titleLabel.text = "UniLLMs"
        titleLabel.font = .systemFont(ofSize: 28.0, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: Metrics.titleTopSpacing
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            )
        ])
    }

    private func configureBottomBar() {
        bottomGlassContainerView.translatesAutoresizingMaskIntoConstraints = false
        bottomGlassContainerView.backgroundColor = .clear
        addSubview(bottomGlassContainerView)

        bottomStackView.axis = .horizontal
        bottomStackView.alignment = .bottom
        bottomStackView.spacing = Metrics.controlSpacing
        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomGlassContainerView.contentView.addSubview(bottomStackView)

        bottomStackView.addArrangedSubview(searchGlassView)
        bottomStackView.addArrangedSubview(settingsGlassView)

        searchGlassView.translatesAutoresizingMaskIntoConstraints = false
        searchGlassView.cornerConfiguration = .corners(
            radius: .fixed(Double(Metrics.controlHeight * 0.5))
        )
        searchGlassView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchGlassView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        settingsGlassView.translatesAutoresizingMaskIntoConstraints = false
        settingsGlassView.cornerConfiguration = .capsule()
        settingsGlassView.setContentHuggingPriority(.required, for: .horizontal)
        settingsGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            bottomGlassContainerView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            bottomGlassContainerView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            bottomGlassContainerView.bottomAnchor.constraint(
                equalTo: keyboardLayoutGuide.topAnchor,
                constant: -Metrics.keyboardBottomSpacing
            ),

            bottomStackView.topAnchor.constraint(equalTo: bottomGlassContainerView.contentView.topAnchor),
            bottomStackView.leadingAnchor.constraint(equalTo: bottomGlassContainerView.contentView.leadingAnchor),
            bottomStackView.trailingAnchor.constraint(equalTo: bottomGlassContainerView.contentView.trailingAnchor),
            bottomStackView.bottomAnchor.constraint(equalTo: bottomGlassContainerView.contentView.bottomAnchor),

            bottomGlassContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            searchGlassView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            settingsGlassView.widthAnchor.constraint(equalToConstant: Metrics.settingsButtonSize),
            settingsGlassView.heightAnchor.constraint(equalToConstant: Metrics.settingsButtonSize)
        ])
    }

    private func configureHistoryList() {
        addLayoutGuide(visibleHistoryLayoutGuide)

        historyTableView.register(HistoryCell.self, forCellReuseIdentifier: HistoryCell.reuseIdentifier)
        historyTableView.dataSource = self
        historyTableView.delegate = self
        historyTableView.backgroundColor = .clear
        historyTableView.separatorStyle = .none
        historyTableView.contentInset = .zero
        historyTableView.contentInsetAdjustmentBehavior = .never
        historyTableView.clipsToBounds = false
        historyTableView.rowHeight = Metrics.historyCellHeight
        historyTableView.estimatedRowHeight = Metrics.historyCellHeight
        historyTableView.sectionHeaderTopPadding = 0.0
        historyTableView.showsVerticalScrollIndicator = false
        historyTableView.showsHorizontalScrollIndicator = false
        historyTableView.keyboardDismissMode = .onDrag
        historyTableView.topEdgeEffect.style = .soft
        historyTableView.bottomEdgeEffect.style = .soft
        historyTableView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(historyTableView, at: 0)

        emptyHistoryLabel.text = String(localized: .chatNoChats)
        emptyHistoryLabel.font = .preferredFont(forTextStyle: .callout)
        emptyHistoryLabel.adjustsFontForContentSizeCategory = true
        emptyHistoryLabel.textColor = .secondaryLabel
        emptyHistoryLabel.textAlignment = .center
        emptyHistoryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyHistoryLabel)

        NSLayoutConstraint.activate([
            visibleHistoryLayoutGuide.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: Metrics.historyTopSpacing
            ),
            visibleHistoryLayoutGuide.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            visibleHistoryLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            visibleHistoryLayoutGuide.bottomAnchor.constraint(
                equalTo: bottomGlassContainerView.topAnchor,
                constant: -Metrics.historyBottomSpacing
            ),

            historyTableView.topAnchor.constraint(
                equalTo: topAnchor
            ),
            historyTableView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            historyTableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            historyTableView.bottomAnchor.constraint(
                equalTo: bottomAnchor
            ),

            emptyHistoryLabel.centerXAnchor.constraint(equalTo: historyTableView.centerXAnchor),
            emptyHistoryLabel.centerYAnchor.constraint(equalTo: visibleHistoryLayoutGuide.centerYAnchor),
            emptyHistoryLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            emptyHistoryLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            )
        ])

        addScrollEdgeInteraction(to: titleLabel, edge: .top)
        addScrollEdgeInteraction(to: bottomGlassContainerView, edge: .bottom)
        updateEmptyHistoryState()
    }

    private func addScrollEdgeInteraction(to view: UIView, edge: UIRectEdge) {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.scrollView = historyTableView
        interaction.edge = edge
        view.addInteraction(interaction)
    }

    private func updateHistoryContentInsets() {
        guard historyTableView.superview != nil else {
            return
        }

        let topInset = max(0.0, titleLabel.frame.maxY + Metrics.historyTopSpacing)
        let bottomInset = max(
            0.0,
            bounds.maxY - bottomGlassContainerView.frame.minY + Metrics.historyBottomSpacing
        )
        let contentInsets = UIEdgeInsets(top: topInset, left: 0.0, bottom: bottomInset, right: 0.0)
        let previousInsets = historyTableView.contentInset

        guard previousInsets != contentInsets else {
            return
        }

        let wasPinnedToTop = historyTableView.contentOffset.y <= -previousInsets.top + CGFloat.ulpOfOne
        historyTableView.contentInset = contentInsets
        historyTableView.scrollIndicatorInsets = contentInsets

        if wasPinnedToTop {
            historyTableView.contentOffset = CGPoint(
                x: historyTableView.contentOffset.x,
                y: -contentInsets.top
            )
        }
    }

    private func configureSearchField() {
        searchRowView.axis = .horizontal
        searchRowView.alignment = .center
        searchRowView.spacing = 8.0
        searchRowView.translatesAutoresizingMaskIntoConstraints = false
        searchGlassView.contentView.addSubview(searchRowView)

        searchIconView.image = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Metrics.searchIconSize,
                weight: .medium
            )
        )
        searchIconView.tintColor = .secondaryLabel
        searchIconView.contentMode = .scaleAspectFit
        searchIconView.setContentHuggingPriority(.required, for: .horizontal)

        searchTextField.placeholder = String(localized: .generalSearch)
        searchTextField.borderStyle = .none
        searchTextField.backgroundColor = .clear
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.returnKeyType = .search
        searchTextField.textColor = .label
        searchTextField.tintColor = .systemBlue
        searchTextField.font = .preferredFont(forTextStyle: .body)
        searchTextField.adjustsFontForContentSizeCategory = true
        searchTextField.accessibilityLabel = String(localized: .generalSearch)
        searchTextField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)

        searchRowView.addArrangedSubview(searchIconView)
        searchRowView.addArrangedSubview(searchTextField)

        NSLayoutConstraint.activate([
            searchRowView.leadingAnchor.constraint(
                equalTo: searchGlassView.contentView.leadingAnchor,
                constant: Metrics.searchHorizontalInset
            ),
            searchRowView.trailingAnchor.constraint(
                equalTo: searchGlassView.contentView.trailingAnchor,
                constant: -Metrics.searchHorizontalInset
            ),
            searchRowView.centerYAnchor.constraint(equalTo: searchGlassView.contentView.centerYAnchor),
            searchRowView.topAnchor.constraint(
                greaterThanOrEqualTo: searchGlassView.contentView.topAnchor,
                constant: 6.0
            ),
            searchRowView.bottomAnchor.constraint(
                lessThanOrEqualTo: searchGlassView.contentView.bottomAnchor,
                constant: -6.0
            )
        ])
    }

    private func configureSettingsButton() {
        settingsButton.tintColor = .label
        settingsButton.setImage(
            UIImage(
                systemName: "gearshape",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: Metrics.settingsIconSize,
                    weight: .regular
                )
            ),
            for: .normal
        )
        settingsButton.accessibilityLabel = String(localized: .generalSettings)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsGlassView.contentView.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: settingsGlassView.contentView.topAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: settingsGlassView.contentView.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: settingsGlassView.contentView.trailingAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: settingsGlassView.contentView.bottomAnchor)
        ])
    }

    @objc private func searchTextDidChange() {
        applyHistoryFilter()
    }

    private func applyHistoryFilter() {
        let query = (searchTextField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let filteredSessions: [ChatSession]
        if query.isEmpty {
            filteredSessions = allSessions
        } else {
            filteredSessions = allSessions.filter { session in
                session.title.lowercased().contains(query)
            }
        }

        let calendar = Calendar.current
        let groupedSessions = Dictionary(grouping: filteredSessions) { session in
            calendar.startOfDay(for: session.updatedAt)
        }

        historySections = groupedSessions.keys
            .sorted(by: >)
            .map { date in
                HistorySection(
                    date: date,
                    sessions: (groupedSessions[date] ?? []).sorted(by: Self.sortSessionsByLastSentDate)
                )
            }

        historyTableView.reloadData()
        updateEmptyHistoryState()
        updateSelectedHistoryRow()
    }

    private func updateEmptyHistoryState() {
        let isEmpty = historySections.allSatisfy { $0.sessions.isEmpty }
        emptyHistoryLabel.isHidden = !isEmpty
        historyTableView.isHidden = isEmpty
    }

    private func updateSelectedHistoryRow() {
        historyTableView.indexPathsForSelectedRows?.forEach {
            historyTableView.deselectRow(at: $0, animated: false)
        }

        guard let selectedSessionID,
              let indexPath = indexPath(for: selectedSessionID) else {
            return
        }

        historyTableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }

    private func indexPath(for sessionID: UUID) -> IndexPath? {
        for (sectionIndex, section) in historySections.enumerated() {
            if let rowIndex = section.sessions.firstIndex(where: { $0.id == sessionID }) {
                return IndexPath(row: rowIndex, section: sectionIndex)
            }
        }

        return nil
    }

    private nonisolated static func sortSessionsByLastSentDate(_ lhs: ChatSession, _ rhs: ChatSession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.createdAt > rhs.createdAt
    }

    private static func makeContainerEffect() -> UIGlassContainerEffect {
        let effect = UIGlassContainerEffect()
        effect.spacing = Metrics.controlSpacing
        return effect
    }

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }
}

private struct HistorySection {
    var date: Date
    var sessions: [ChatSession]
}

private final class HistoryDateHeaderView: UIView {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        return formatter
    }()

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func update(date: Date) {
        titleLabel.text = Self.dateFormatter.string(from: date)
    }

    private func configure() {
        backgroundColor = .clear

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24.0),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16.0),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6.0),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6.0)
        ])
    }
}

private final class HistoryCell: UITableViewCell {
    static let reuseIdentifier = "HistoryCell"

    private enum Metrics {
        static let horizontalContentInset: CGFloat = 24.0
        static let verticalContentInset: CGFloat = 8.0
        static let backgroundHorizontalInset: CGFloat = 12.0
        static let backgroundVerticalInset: CGFloat = 2.0
        static let selectedCornerRadius: CGFloat = 14.0
    }

    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func configure(with session: ChatSession) {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = trimmed.isEmpty ? String(localized: .chatNewChat) : trimmed
    }

    private func configure() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Metrics.horizontalContentInset
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Metrics.horizontalContentInset
            ),
            titleLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Metrics.verticalContentInset
            ),
            titleLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Metrics.verticalContentInset
            )
        ])

        configureBackgroundConfiguration()
    }

    private func configureBackgroundConfiguration() {
        var background = defaultBackgroundConfiguration()
        background.backgroundInsets = NSDirectionalEdgeInsets(
            top: Metrics.backgroundVerticalInset,
            leading: Metrics.backgroundHorizontalInset,
            bottom: Metrics.backgroundVerticalInset,
            trailing: Metrics.backgroundHorizontalInset
        )
        background.cornerRadius = Metrics.selectedCornerRadius
        backgroundConfiguration = background
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)

        backgroundConfiguration?.backgroundColor = state.isSelected || state.isHighlighted
            ? Self.selectionBackgroundColor
            : .clear
    }

    private static var selectionBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.1)
                : UIColor.black.withAlphaComponent(0.1)
        }
    }
}

extension SideMenuView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        historySections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        historySections[section].sessions.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: HistoryCell.reuseIdentifier,
            for: indexPath
        ) as? HistoryCell ?? HistoryCell(style: .default, reuseIdentifier: HistoryCell.reuseIdentifier)
        cell.configure(with: historySections[indexPath.section].sessions[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let session = historySections[indexPath.section].sessions[indexPath.row]
        selectedSessionID = session.id
        onSessionSelected?(session)
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let session = historySections[indexPath.section].sessions[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let deleteAction = UIAction(
                title: String(localized: .generalDelete),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.onSessionDeleted?(session)
            }
            return UIMenu(children: [deleteAction])
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        historySections.count > 1 ? Metrics.historyHeaderHeight : CGFloat.leastNonzeroMagnitude
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard historySections.count > 1 else {
            return nil
        }

        let headerView = HistoryDateHeaderView()
        headerView.update(date: historySections[section].date)
        return headerView
    }
}
