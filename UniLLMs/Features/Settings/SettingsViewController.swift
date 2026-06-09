//
//  SettingsViewController.swift
//  UniLLMs
//
//  Hosts the SwiftUI settings experience.
//  Created by Zayrick on 2026/5/11.
//

import Observation
import SwiftUI
import UIKit

final class SettingsViewController: UIHostingController<SettingsForm> {
    private let model: SettingsModel
    private let router: SettingsRouter

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        let model = SettingsModel(dependencies: dependencies)
        let router = SettingsRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(rootView: SettingsForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = SettingsModel(dependencies: dependencies)
        let router = SettingsRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: SettingsForm(model: model, router: router))
        router.hostViewController = self
    }
}

struct SettingsForm: View {
    private let model: SettingsModel
    private let router: SettingsRouter

    fileprivate init(
        model: SettingsModel,
        router: SettingsRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Form {
            modelAndConversationSection
            capabilitiesSection
            appAndSystemSection
        }
        .navigationTitle(String(localized: .generalSettings))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: router.close) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(String(localized: "general.close"))
            }
        }
    }

    private var modelAndConversationSection: some View {
        Section(String(localized: "settings.section.model_and_conversation")) {
            SettingsNavigationRow(
                title: String(localized: .settingsRowProvidersTitle),
                symbolName: "globe",
                tintColor: .systemBlue,
                action: router.showProviders
            )

            SettingsNavigationRow(
                title: String(localized: .settingsRowSystemPromptsTitle),
                symbolName: "text.quote",
                tintColor: .systemPurple,
                action: router.showSystemPrompts
            )
        }
    }

    private var capabilitiesSection: some View {
        Section(String(localized: "settings.section.capabilities")) {
            SettingsNavigationRow(
                title: String(localized: .settingsRowMemoriesTitle),
                symbolName: "brain.head.profile",
                tintColor: .systemTeal,
                action: router.showMemories
            )

            SettingsNavigationRow(
                title: String(localized: .settingsRowToolsTitle),
                symbolName: "hammer",
                tintColor: .systemGreen,
                action: router.showTools
            )
        }
    }

    private var appAndSystemSection: some View {
        Section(String(localized: "settings.section.app_and_system")) {
            Picker(selection: colorModeBinding) {
                ForEach(AppColorMode.allCases) { mode in
                    Text(model.title(for: mode)).tag(mode)
                }
            } label: {
                SettingsRowLabel(
                    title: String(localized: "settings.color_mode.title"),
                    symbolName: "circle.lefthalf.filled",
                    tintColor: .systemBlue
                )
            }
            .pickerStyle(.menu)

            Toggle(isOn: backgroundRuntimeBinding) {
                SettingsRowLabel(
                    title: String(localized: "settings.background_runtime.title"),
                    symbolName: "arrow.triangle.2.circlepath.circle",
                    tintColor: model.isBackgroundRuntimeEnabled ? .systemOrange : .secondaryLabel
                )
            }

            Toggle(isOn: keepsScreenAwakeDuringAIOutputBinding) {
                SettingsRowLabel(
                    title: String(localized: "settings.keep_screen_awake_ai_output.title"),
                    symbolName: "display",
                    tintColor: model.keepsScreenAwakeDuringAIOutput ? .systemGreen : .secondaryLabel
                )
            }

            SettingsNavigationRow(
                title: String(localized: "settings.row.permissions.title"),
                symbolName: "key",
                tintColor: .systemIndigo,
                action: router.showPermissions
            )

            SettingsNavigationRow(
                title: String(localized: "settings.row.about.title"),
                symbolName: "info.circle",
                tintColor: .systemGray,
                action: router.showAbout
            )
        }
    }

    private var backgroundRuntimeBinding: Binding<Bool> {
        Binding {
            model.isBackgroundRuntimeEnabled
        } set: { isEnabled in
            model.setBackgroundRuntimeEnabled(isEnabled)
        }
    }

    private var colorModeBinding: Binding<AppColorMode> {
        Binding {
            model.colorMode
        } set: { colorMode in
            model.setColorMode(colorMode)
        }
    }

    private var keepsScreenAwakeDuringAIOutputBinding: Binding<Bool> {
        Binding {
            model.keepsScreenAwakeDuringAIOutput
        } set: { isEnabled in
            model.setKeepsScreenAwakeDuringAIOutput(isEnabled)
        }
    }
}

@MainActor
private final class SettingsRouter {
    weak var hostViewController: UIViewController?

    private let dependencies: AppDependencyContainer

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
    }

    func close() {
        hostViewController?.dismiss(animated: true)
    }

    func showProviders() {
        push(LLMsProviderViewController(dependencies: dependencies))
    }

    func showSystemPrompts() {
        push(SystemPromptSettingsViewController(dependencies: dependencies))
    }

    func showMemories() {
        push(MemoryListViewController(dependencies: dependencies))
    }

    func showTools() {
        push(ToolsViewController(dependencies: dependencies))
    }

    func showPermissions() {
        push(PermissionsViewController())
    }

    func showAbout() {
        push(AboutViewController())
    }

    private func push(_ viewController: UIViewController) {
        hostViewController?.navigationController?.pushViewController(viewController, animated: true)
    }
}

@MainActor
@Observable
private final class SettingsModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer

    var isBackgroundRuntimeEnabled: Bool
    var colorMode: AppColorMode
    var keepsScreenAwakeDuringAIOutput: Bool

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        isBackgroundRuntimeEnabled = dependencies.appSettingsStore.isBackgroundRuntimeEnabled
        colorMode = dependencies.appSettingsStore.colorMode
        keepsScreenAwakeDuringAIOutput = dependencies.appSettingsStore.keepsScreenAwakeDuringAIOutput
    }

    func setBackgroundRuntimeEnabled(_ isEnabled: Bool) {
        guard isBackgroundRuntimeEnabled != isEnabled else {
            return
        }

        isBackgroundRuntimeEnabled = isEnabled
        dependencies.appSettingsStore.isBackgroundRuntimeEnabled = isEnabled
    }

    func setColorMode(_ mode: AppColorMode) {
        guard colorMode != mode else {
            return
        }

        colorMode = mode
        dependencies.appSettingsStore.colorMode = mode
        AppAppearanceController.apply(mode)
    }

    func setKeepsScreenAwakeDuringAIOutput(_ isEnabled: Bool) {
        guard keepsScreenAwakeDuringAIOutput != isEnabled else {
            return
        }

        keepsScreenAwakeDuringAIOutput = isEnabled
        dependencies.appSettingsStore.keepsScreenAwakeDuringAIOutput = isEnabled
    }

    func title(for colorMode: AppColorMode) -> String {
        switch colorMode {
        case .system:
            return String(localized: "settings.color_mode.system")
        case .light:
            return String(localized: "settings.color_mode.light")
        case .dark:
            return String(localized: "settings.color_mode.dark")
        }
    }
}
