//
//  SystemPromptSettingsViewController.swift
//  UniLLMs
//
//  Shows automatic context and saved prompt settings.
//

import Observation
import SwiftUI
import UIKit

final class SystemPromptSettingsViewController: UIHostingController<SystemPromptSettingsForm> {
    private let model: SystemPromptSettingsModel
    private let router: SystemPromptSettingsRouter

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        let model = SystemPromptSettingsModel(dependencies: dependencies)
        let router = SystemPromptSettingsRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(rootView: SystemPromptSettingsForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = SystemPromptSettingsModel(dependencies: dependencies)
        let router = SystemPromptSettingsRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: SystemPromptSettingsForm(model: model, router: router))
        router.hostViewController = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshContent()
    }
}

struct SystemPromptSettingsForm: View {
    private let model: SystemPromptSettingsModel
    private let router: SystemPromptSettingsRouter

    fileprivate init(
        model: SystemPromptSettingsModel,
        router: SystemPromptSettingsRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Form {
            automaticContextSection
            memoryConfigurationSection
            customPromptsSection
        }
        .navigationTitle(String(localized: .settingsRowSystemPromptsTitle))
        .animation(.default, value: model.memoryInjectionSettings.isEnabled)
    }

    private var automaticContextSection: some View {
        Section {
            Toggle(isOn: currentDateBinding) {
                SystemPromptSettingsRowLabel(
                    title: String(localized: "system_prompts.settings.row.current_date.title"),
                    subtitle: String(localized: "system_prompts.settings.row.current_date.detail"),
                    symbolName: "clock",
                    tintColor: model.systemPromptInjectionSettings.isCurrentDateEnabled ? .systemOrange : .secondaryLabel
                )
            }

            Toggle(isOn: memoryEnabledBinding) {
                SystemPromptSettingsRowLabel(
                    title: String(localized: "system_prompts.settings.row.memory.title"),
                    subtitle: String(localized: "system_prompts.settings.row.memory.detail"),
                    symbolName: "brain.head.profile",
                    tintColor: model.memoryInjectionSettings.isEnabled ? .systemTeal : .secondaryLabel
                )
            }
        } header: {
            Text(String(localized: "system_prompts.settings.section.automatic_context"))
        } footer: {
            Text(String(localized: "system_prompts.settings.footer.automatic_context"))
        }
    }

    @ViewBuilder
    private var memoryConfigurationSection: some View {
        if model.memoryInjectionSettings.isEnabled {
            Section(String(localized: "system_prompts.settings.section.memory_context")) {
                Picker(selection: memoryFilterBinding) {
                    ForEach(MemoryInjectionFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                } label: {
                    SystemPromptSettingsRowLabel(
                        title: String(localized: .memoriesMemoryFilter),
                        subtitle: nil,
                        symbolName: "line.3.horizontal.decrease.circle",
                        tintColor: .systemTeal
                    )
                }
                .pickerStyle(.menu)
                .accessibilityLabel(String(localized: .memoriesAccessibilityInjectionFilter))

                Picker(selection: maximumMemoriesBinding) {
                    ForEach(model.selectableMaximumMemories, id: \.self) { maximumMemories in
                        Text(model.menuTitle(forMaximumMemories: maximumMemories))
                            .tag(maximumMemories)
                    }
                } label: {
                    SystemPromptSettingsRowLabel(
                        title: String(localized: .memoriesMemoryLimit),
                        subtitle: nil,
                        symbolName: "number.circle",
                        tintColor: .systemTeal
                    )
                }
                .pickerStyle(.menu)
                .accessibilityLabel(String(localized: .memoriesAccessibilityInjectionLimit))
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var customPromptsSection: some View {
        Section(String(localized: "system_prompts.settings.section.custom_prompts")) {
            Button(action: router.showCustomPrompts) {
                HStack(spacing: 12) {
                    SystemPromptSettingsRowLabel(
                        title: String(localized: "system_prompts.custom.title"),
                        subtitle: model.promptCountDescription,
                        symbolName: "text.quote",
                        tintColor: .systemPurple
                    )
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var currentDateBinding: Binding<Bool> {
        Binding {
            model.systemPromptInjectionSettings.isCurrentDateEnabled
        } set: { isEnabled in
            model.setCurrentDateEnabled(isEnabled)
        }
    }

    private var memoryEnabledBinding: Binding<Bool> {
        Binding {
            model.memoryInjectionSettings.isEnabled
        } set: { isEnabled in
            withAnimation(.default) {
                model.setMemoryEnabled(isEnabled)
            }
        }
    }

    private var memoryFilterBinding: Binding<MemoryInjectionFilter> {
        Binding {
            model.memoryInjectionSettings.filter
        } set: { filter in
            model.setMemoryFilter(filter)
        }
    }

    private var maximumMemoriesBinding: Binding<Int?> {
        Binding {
            model.memoryInjectionSettings.maximumMemories
        } set: { maximumMemories in
            model.setMaximumMemories(maximumMemories)
        }
    }
}

private struct SystemPromptSettingsRowLabel: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let tintColor: UIColor

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(Color(uiColor: tintColor))
        }
    }
}

@MainActor
private final class SystemPromptSettingsRouter {
    weak var hostViewController: UIViewController?

    private let dependencies: AppDependencyContainer

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
    }

    func showCustomPrompts() {
        hostViewController?.navigationController?.pushViewController(
            SystemPromptsViewController(dependencies: dependencies),
            animated: true
        )
    }
}

@MainActor
@Observable
private final class SystemPromptSettingsModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer
    @ObservationIgnored private var systemPromptSettingsObservation: NSObjectProtocol?
    @ObservationIgnored private var memorySettingsObservation: NSObjectProtocol?
    @ObservationIgnored private var systemPromptObservation: NSObjectProtocol?

    var systemPromptInjectionSettings = SystemPromptInjectionSettings()
    var memoryInjectionSettings = MemoryInjectionSettings()
    var promptCount = 0

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        installStoreObservers()
        refreshContent()
    }

    deinit {
        if let systemPromptSettingsObservation {
            NotificationCenter.default.removeObserver(systemPromptSettingsObservation)
        }
        if let memorySettingsObservation {
            NotificationCenter.default.removeObserver(memorySettingsObservation)
        }
        if let systemPromptObservation {
            NotificationCenter.default.removeObserver(systemPromptObservation)
        }
    }

    func refreshContent() {
        refreshSystemPromptInjectionSettings()
        refreshMemoryInjectionSettings()
        refreshPromptCount()
    }

    func setCurrentDateEnabled(_ isEnabled: Bool) {
        var updatedSettings = systemPromptInjectionSettings
        updatedSettings.isCurrentDateEnabled = isEnabled
        saveSystemPromptInjectionSettings(updatedSettings)
    }

    func setMemoryEnabled(_ isEnabled: Bool) {
        var updatedSettings = memoryInjectionSettings
        updatedSettings.isEnabled = isEnabled
        saveMemoryInjectionSettings(updatedSettings)
    }

    func setMemoryFilter(_ filter: MemoryInjectionFilter) {
        var updatedSettings = memoryInjectionSettings
        updatedSettings.filter = filter
        saveMemoryInjectionSettings(updatedSettings)
    }

    func setMaximumMemories(_ maximumMemories: Int?) {
        var updatedSettings = memoryInjectionSettings
        updatedSettings.maximumMemories = maximumMemories
        saveMemoryInjectionSettings(updatedSettings)
    }

    var selectableMaximumMemories: [Int?] {
        var values = MemoryInjectionSettings.selectableMaximumMemories
        if let maximumMemories = memoryInjectionSettings.maximumMemories,
           !values.contains(maximumMemories) {
            values.append(maximumMemories)
        }

        return [nil] + values.sorted().map(Optional.some)
    }

    func menuTitle(forMaximumMemories maximumMemories: Int?) -> String {
        guard let maximumMemories else {
            return String(localized: .memoriesNoLimit)
        }

        return "\(maximumMemories)"
    }

    var promptCountDescription: String {
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

    private func installStoreObservers() {
        systemPromptSettingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsSystemPromptSettingsStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSystemPromptInjectionSettings()
            }
        }

        memorySettingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMemorySettingsStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMemoryInjectionSettings()
            }
        }

        systemPromptObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsSystemPromptStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPromptCount()
            }
        }
    }

    private func refreshSystemPromptInjectionSettings() {
        systemPromptInjectionSettings = dependencies.systemPromptSettingsStore.loadInjectionSettings()
    }

    private func refreshMemoryInjectionSettings() {
        memoryInjectionSettings = dependencies.memoryManager.memoryInjectionSettings()
    }

    private func refreshPromptCount() {
        promptCount = dependencies.systemPromptManager.savedPrompts().count
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

        memoryInjectionSettings = settings
        dependencies.memoryManager.saveMemoryInjectionSettings(settings)
    }
}
