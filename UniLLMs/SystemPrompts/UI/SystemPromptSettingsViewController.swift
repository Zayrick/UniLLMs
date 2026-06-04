//
//  SystemPromptSettingsViewController.swift
//  UniLLMs
//
//  Shows automatic context and saved prompt settings.
//

import UIKit

final class SystemPromptSettingsViewController: UITableViewController {
    private enum Section: Equatable {
        case automaticContext
        case memoryConfiguration
        case customPrompts

        static func visible(memoryEnabled: Bool) -> [Section] {
            memoryEnabled
                ? [.automaticContext, .memoryConfiguration, .customPrompts]
                : [.automaticContext, .customPrompts]
        }

        var headerTitle: String? {
            switch self {
            case .automaticContext:
                return String(localized: "system_prompts.settings.section.automatic_context")
            case .memoryConfiguration:
                return String(localized: "system_prompts.settings.section.memory_context")
            case .customPrompts:
                return String(localized: "system_prompts.settings.section.custom_prompts")
            }
        }

        var footerTitle: String? {
            switch self {
            case .automaticContext:
                return String(localized: "system_prompts.settings.footer.automatic_context")
            case .memoryConfiguration:
                return nil
            case .customPrompts:
                return nil
            }
        }
    }

    private enum AutomaticContextRow: Int, CaseIterable {
        case currentDate
        case memory
    }

    private enum MemoryConfigurationRow: Int, CaseIterable {
        case filter
        case maximumMemories
    }

    private enum ReuseIdentifier {
        static let automaticContextCell = "SystemPromptAutomaticContextCell"
        static let memoryConfigurationCell = "SystemPromptMemoryConfigurationCell"
        static let customPromptCell = "SystemPromptCustomPromptCell"
    }

    private let dependencies: AppDependencyContainer
    private var systemPromptInjectionSettings = SystemPromptInjectionSettings()
    private var memoryInjectionSettings = MemoryInjectionSettings()
    private var sections = Section.visible(memoryEnabled: MemoryInjectionSettings().isEnabled)
    private var promptCount = 0
    private var storeObservations: [NSObjectProtocol] = []

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

        title = String(localized: .settingsRowSystemPromptsTitle)
        installStoreObservers()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadContent()
    }

    private func installStoreObservers() {
        let systemPromptSettingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsSystemPromptSettingsStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSystemPromptInjectionSettings()
        }
        let memorySettingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMemorySettingsStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadMemoryInjectionSettings()
        }
        let systemPromptObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsSystemPromptStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadPromptCount()
        }
        storeObservations = [
            systemPromptSettingsObservation,
            memorySettingsObservation,
            systemPromptObservation
        ]
    }

    private func reloadContent() {
        systemPromptInjectionSettings = dependencies.systemPromptSettingsStore.loadInjectionSettings()
        memoryInjectionSettings = dependencies.memoryManager.memoryInjectionSettings()
        sections = Section.visible(memoryEnabled: memoryInjectionSettings.isEnabled)
        promptCount = dependencies.systemPromptManager.savedPrompts().count
        tableView.reloadData()
    }

    private func reloadSystemPromptInjectionSettings() {
        let updatedSettings = dependencies.systemPromptSettingsStore.loadInjectionSettings()
        guard updatedSettings != systemPromptInjectionSettings else {
            return
        }

        systemPromptInjectionSettings = updatedSettings
        updateVisibleAutomaticContextCell(row: .currentDate)
    }

    private func reloadMemoryInjectionSettings() {
        let updatedSettings = dependencies.memoryManager.memoryInjectionSettings()
        guard updatedSettings != memoryInjectionSettings else {
            return
        }

        let wasMemoryConfigurationVisible = isMemoryConfigurationVisible
        memoryInjectionSettings = updatedSettings
        sections = Section.visible(memoryEnabled: updatedSettings.isEnabled)
        updateVisibleAutomaticContextCell(row: .memory)
        updateMemoryConfigurationSection(wasVisible: wasMemoryConfigurationVisible)
        updateVisibleMemoryConfigurationCells()
    }

    private func reloadPromptCount() {
        let updatedCount = dependencies.systemPromptManager.savedPrompts().count
        guard updatedCount != promptCount else {
            return
        }

        promptCount = updatedCount
        updateVisibleCustomPromptCell()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionType(at: section) {
        case .automaticContext:
            return AutomaticContextRow.allCases.count
        case .memoryConfiguration:
            return MemoryConfigurationRow.allCases.count
        case .customPrompts:
            return 1
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sectionType(at: section)?.headerTitle
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sectionType(at: section)?.footerTitle
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch sectionType(at: indexPath.section) {
        case .automaticContext:
            return automaticContextCell(for: indexPath)
        case .memoryConfiguration:
            return memoryConfigurationCell(for: indexPath)
        case .customPrompts:
            return customPromptsCell()
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard sectionType(at: indexPath.section) == .customPrompts else {
            return
        }

        navigationController?.pushViewController(
            SystemPromptsViewController(dependencies: dependencies),
            animated: true
        )
    }

    private func automaticContextCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let row = AutomaticContextRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.automaticContextCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.automaticContextCell)
        configureAutomaticContextCellContent(cell, row: row)

        let toggle = UISwitch()
        toggle.isOn = isAutomaticContextRowEnabled(row)
        let action: Selector = row == .currentDate
            ? #selector(toggleCurrentDateInjection(_:))
            : #selector(toggleMemoryInjection(_:))
        toggle.addTarget(
            self,
            action: action,
            for: .valueChanged
        )
        toggle.accessibilityLabel = automaticContextRowTitle(row)
        cell.accessoryView = toggle
        cell.accessoryType = .none
        cell.selectionStyle = .none
        return cell
    }

    private func configureAutomaticContextCellContent(
        _ cell: UITableViewCell,
        row: AutomaticContextRow
    ) {
        let isEnabled = isAutomaticContextRowEnabled(row)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = automaticContextRowTitle(row)
        contentConfiguration.secondaryText = automaticContextRowDetail(row)
        contentConfiguration.secondaryTextProperties.numberOfLines = 0
        contentConfiguration.image = UIImage(systemName: automaticContextRowSymbolName(row))
        contentConfiguration.imageProperties.tintColor = isEnabled ? automaticContextRowEnabledTintColor(row) : .secondaryLabel
        cell.contentConfiguration = contentConfiguration
    }

    private func memoryConfigurationCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let row = MemoryConfigurationRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        switch row {
        case .filter:
            return memoryFilterCell()
        case .maximumMemories:
            return memoryLimitCell()
        }
    }

    private func memoryFilterCell() -> UITableViewCell {
        let cell = memoryConfigurationCell()
        configureMemoryFilterCell(cell)
        return cell
    }

    private func memoryLimitCell() -> UITableViewCell {
        let cell = memoryConfigurationCell()
        configureMemoryLimitCell(cell)
        return cell
    }

    private func memoryConfigurationCell() -> MemoryConfigurationCell {
        tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.memoryConfigurationCell) as? MemoryConfigurationCell
            ?? MemoryConfigurationCell(reuseIdentifier: ReuseIdentifier.memoryConfigurationCell)
    }

    private func configureMemoryFilterCell(_ cell: MemoryConfigurationCell) {
        cell.configure(
            title: String(localized: .memoriesMemoryFilter),
            symbolName: "line.3.horizontal.decrease.circle",
            tintColor: .systemTeal,
            menuTitle: memoryInjectionSettings.filter.title,
            menu: memoryFilterMenu(),
            accessibilityLabel: String(localized: .memoriesAccessibilityInjectionFilter)
        )
    }

    private func configureMemoryLimitCell(_ cell: MemoryConfigurationCell) {
        cell.configure(
            title: String(localized: .memoriesMemoryLimit),
            symbolName: "number.circle",
            tintColor: .systemTeal,
            menuTitle: memoryLimitMenuTitle,
            menu: memoryLimitMenu(),
            accessibilityLabel: String(localized: .memoriesAccessibilityInjectionLimit)
        )
    }

    private func customPromptsCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier.customPromptCell)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: ReuseIdentifier.customPromptCell)
        configureCustomPromptCellContent(cell)
        cell.accessoryView = nil
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    private func configureCustomPromptCellContent(_ cell: UITableViewCell) {
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = String(localized: "system_prompts.custom.title")
        contentConfiguration.secondaryText = promptCountDescription
        contentConfiguration.image = UIImage(systemName: "text.quote")
        contentConfiguration.imageProperties.tintColor = .systemPurple
        cell.contentConfiguration = contentConfiguration
    }

    @objc private func toggleCurrentDateInjection(_ sender: UISwitch) {
        var updatedSettings = systemPromptInjectionSettings
        updatedSettings.isCurrentDateEnabled = sender.isOn
        saveSystemPromptInjectionSettings(updatedSettings)
        updateVisibleAutomaticContextCell(row: .currentDate)
    }

    @objc private func toggleMemoryInjection(_ sender: UISwitch) {
        var updatedSettings = memoryInjectionSettings
        updatedSettings.isEnabled = sender.isOn
        saveMemoryInjectionSettings(updatedSettings)
    }

    private func memoryFilterMenu() -> UIMenu {
        let actions = MemoryInjectionFilter.allCases.map { filter in
            UIAction(
                title: filter.title,
                state: filter == memoryInjectionSettings.filter ? .on : .off
            ) { [weak self] _ in
                guard let self else {
                    return
                }

                var updatedSettings = self.memoryInjectionSettings
                updatedSettings.filter = filter
                self.saveMemoryInjectionSettings(updatedSettings)
            }
        }

        return UIMenu(options: .singleSelection, children: actions)
    }

    private func memoryLimitMenu() -> UIMenu {
        let actions = selectableMaximumMemories.map { maximumMemories -> UIAction in
            let title = menuTitle(forMaximumMemories: maximumMemories)
            return UIAction(
                title: title,
                state: maximumMemories == memoryInjectionSettings.maximumMemories ? .on : .off
            ) { [weak self] _ in
                guard let self else {
                    return
                }

                var updatedSettings = self.memoryInjectionSettings
                updatedSettings.maximumMemories = maximumMemories
                self.saveMemoryInjectionSettings(updatedSettings)
            }
        }

        return UIMenu(options: .singleSelection, children: actions)
    }

    private func saveSystemPromptInjectionSettings(_ settings: SystemPromptInjectionSettings) {
        guard settings != systemPromptInjectionSettings else {
            return
        }

        systemPromptInjectionSettings = settings
        dependencies.systemPromptSettingsStore.saveInjectionSettings(settings)
    }

    private func saveMemoryInjectionSettings(_ settings: MemoryInjectionSettings) {
        guard settings != memoryInjectionSettings else {
            return
        }

        let wasMemoryConfigurationVisible = isMemoryConfigurationVisible
        memoryInjectionSettings = settings
        sections = Section.visible(memoryEnabled: settings.isEnabled)
        dependencies.memoryManager.saveMemoryInjectionSettings(settings)
        updateVisibleAutomaticContextCell(row: .memory)
        updateMemoryConfigurationSection(wasVisible: wasMemoryConfigurationVisible)
        updateVisibleMemoryConfigurationCells()
    }

    private func updateVisibleAutomaticContextCell(row: AutomaticContextRow) {
        guard let cell = tableView.cellForRow(at: indexPath(for: row)) else {
            return
        }

        configureAutomaticContextCellContent(cell, row: row)
        guard let toggle = cell.accessoryView as? UISwitch else {
            return
        }

        let isEnabled = isAutomaticContextRowEnabled(row)
        if toggle.isOn != isEnabled {
            toggle.setOn(isEnabled, animated: false)
        }
    }

    private func updateVisibleMemoryConfigurationCells() {
        updateVisibleMemoryConfigurationCell(row: .filter, configure: configureMemoryFilterCell)
        updateVisibleMemoryConfigurationCell(row: .maximumMemories, configure: configureMemoryLimitCell)
    }

    private func updateVisibleMemoryConfigurationCell(
        row: MemoryConfigurationRow,
        configure: (MemoryConfigurationCell) -> Void
    ) {
        guard let indexPath = indexPath(for: row),
              let cell = tableView.cellForRow(at: indexPath),
              let memoryConfigurationCell = cell as? MemoryConfigurationCell else {
            return
        }

        configure(memoryConfigurationCell)
    }

    private func updateVisibleCustomPromptCell() {
        guard let indexPath = indexPathForCustomPrompts(),
              let cell = tableView.cellForRow(at: indexPath) else {
            return
        }

        configureCustomPromptCellContent(cell)
    }

    private func updateMemoryConfigurationSection(wasVisible: Bool) {
        guard wasVisible != isMemoryConfigurationVisible else {
            return
        }

        let sectionIndex = 1
        if isMemoryConfigurationVisible {
            tableView.insertSections(IndexSet(integer: sectionIndex), with: .automatic)
        } else {
            tableView.deleteSections(IndexSet(integer: sectionIndex), with: .automatic)
        }
    }

    private func indexPath(for row: AutomaticContextRow) -> IndexPath {
        IndexPath(row: row.rawValue, section: 0)
    }

    private func indexPath(for row: MemoryConfigurationRow) -> IndexPath? {
        guard let section = sections.firstIndex(of: .memoryConfiguration) else {
            return nil
        }

        return IndexPath(row: row.rawValue, section: section)
    }

    private func indexPathForCustomPrompts() -> IndexPath? {
        guard let section = sections.firstIndex(of: .customPrompts) else {
            return nil
        }

        return IndexPath(row: 0, section: section)
    }

    private func sectionType(at index: Int) -> Section? {
        guard sections.indices.contains(index) else {
            return nil
        }

        return sections[index]
    }

    private var isMemoryConfigurationVisible: Bool {
        sections.contains(.memoryConfiguration)
    }

    private func isAutomaticContextRowEnabled(_ row: AutomaticContextRow) -> Bool {
        switch row {
        case .currentDate:
            return systemPromptInjectionSettings.isCurrentDateEnabled
        case .memory:
            return memoryInjectionSettings.isEnabled
        }
    }

    private func automaticContextRowTitle(_ row: AutomaticContextRow) -> String {
        switch row {
        case .currentDate:
            return String(localized: "system_prompts.settings.row.current_date.title")
        case .memory:
            return String(localized: "system_prompts.settings.row.memory.title")
        }
    }

    private func automaticContextRowDetail(_ row: AutomaticContextRow) -> String {
        switch row {
        case .currentDate:
            return String(localized: "system_prompts.settings.row.current_date.detail")
        case .memory:
            return String(localized: "system_prompts.settings.row.memory.detail")
        }
    }

    private func automaticContextRowSymbolName(_ row: AutomaticContextRow) -> String {
        switch row {
        case .currentDate:
            return "clock"
        case .memory:
            return "brain.head.profile"
        }
    }

    private func automaticContextRowEnabledTintColor(_ row: AutomaticContextRow) -> UIColor {
        switch row {
        case .currentDate:
            return .systemOrange
        case .memory:
            return .systemTeal
        }
    }

    private var selectableMaximumMemories: [Int?] {
        var values = MemoryInjectionSettings.selectableMaximumMemories
        if let maximumMemories = memoryInjectionSettings.maximumMemories,
           !values.contains(maximumMemories) {
            values.append(maximumMemories)
        }

        return [nil] + values.sorted().map(Optional.some)
    }

    private var memoryLimitMenuTitle: String {
        menuTitle(forMaximumMemories: memoryInjectionSettings.maximumMemories)
    }

    private func menuTitle(forMaximumMemories maximumMemories: Int?) -> String {
        guard let maximumMemories else {
            return String(localized: .memoriesNoLimit)
        }

        return "\(maximumMemories)"
    }

    private var promptCountDescription: String {
        switch promptCount {
        case 0:
            return String(localized: "system_prompts.count.none")
        case 1:
            return String(localized: "system_prompts.count.one")
        default:
            return String.localizedStringWithFormat(
                String(localized: "system_prompts.count.format"),
                promptCount
            )
        }
    }
}

private final class MemoryConfigurationCell: UITableViewCell {
    private enum Metrics {
        static let symbolSize: CGFloat = 24
        static let horizontalSpacing: CGFloat = 12
        static let menuSpacing: CGFloat = 8
    }

    private let rowStackView = UIStackView()
    private let symbolImageView = UIImageView()
    private let titleLabel = UILabel()
    private let menuButton = UIButton(configuration: .plain())

    init(reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    func configure(
        title: String,
        symbolName: String,
        tintColor: UIColor,
        menuTitle: String,
        menu: UIMenu,
        accessibilityLabel: String
    ) {
        titleLabel.text = title
        symbolImageView.image = UIImage(systemName: symbolName)
        symbolImageView.tintColor = tintColor

        var configuration = menuButton.configuration ?? .plain()
        configuration.title = menuTitle
        configuration.titleLineBreakMode = .byTruncatingTail
        menuButton.configuration = configuration
        menuButton.menu = menu
        menuButton.accessibilityLabel = accessibilityLabel
        menuButton.accessibilityValue = menuTitle
    }

    private func configureLayout() {
        selectionStyle = .none
        accessoryType = .none

        rowStackView.axis = .horizontal
        rowStackView.alignment = .center
        rowStackView.spacing = Metrics.horizontalSpacing
        rowStackView.translatesAutoresizingMaskIntoConstraints = false

        symbolImageView.contentMode = .scaleAspectFit
        symbolImageView.setContentHuggingPriority(.required, for: .horizontal)
        symbolImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        menuButton.showsMenuAsPrimaryAction = true
        menuButton.changesSelectionAsPrimaryAction = true
        menuButton.contentHorizontalAlignment = .trailing
        menuButton.titleLabel?.numberOfLines = 1
        menuButton.setContentHuggingPriority(.required, for: .horizontal)
        menuButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        rowStackView.addArrangedSubview(symbolImageView)
        rowStackView.addArrangedSubview(titleLabel)
        rowStackView.setCustomSpacing(Metrics.menuSpacing, after: titleLabel)
        rowStackView.addArrangedSubview(menuButton)
        contentView.addSubview(rowStackView)

        NSLayoutConstraint.activate([
            rowStackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rowStackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            symbolImageView.widthAnchor.constraint(equalToConstant: Metrics.symbolSize),
            symbolImageView.heightAnchor.constraint(equalToConstant: Metrics.symbolSize)
        ])
    }
}
