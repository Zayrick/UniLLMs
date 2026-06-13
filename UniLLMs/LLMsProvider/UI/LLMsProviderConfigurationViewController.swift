//
//  LLMsProviderConfigurationViewController.swift
//  UniLLMs
//
//  Hosts provider configuration fields and model list management.
//  Created by Zayrick on 2026/5/11.
//

import Observation
import SwiftUI
import UIKit

final class LLMsProviderConfigurationViewController: UIHostingController<LLMsProviderConfigurationForm> {
    private let model: LLMsProviderConfigurationModel
    private let router: LLMsProviderConfigurationRouter

    init(
        provider: LLMsProviderRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewProvider: Bool = false
    ) {
        let model = LLMsProviderConfigurationModel(
            provider: provider,
            dependencies: dependencies,
            isNewProvider: isNewProvider
        )
        let router = LLMsProviderConfigurationRouter()
        self.model = model
        self.router = router
        super.init(rootView: LLMsProviderConfigurationForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let provider = (try? dependencies.providerManager.makeDefaultProviderDraft())
            ?? LLMsProviderRecord(
                kind: LLMsProviderKind(rawValue: ""),
                name: "",
                configuration: LLMsProviderConfiguration()
            )
        let model = LLMsProviderConfigurationModel(
            provider: provider,
            dependencies: dependencies,
            isNewProvider: true
        )
        let router = LLMsProviderConfigurationRouter()
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: LLMsProviderConfigurationForm(model: model, router: router))
        router.hostViewController = self
    }
}

typealias ProviderConfigurationViewController = LLMsProviderConfigurationViewController

struct LLMsProviderConfigurationForm: View {
    private let model: LLMsProviderConfigurationModel
    private let router: LLMsProviderConfigurationRouter

    fileprivate init(
        model: LLMsProviderConfigurationModel,
        router: LLMsProviderConfigurationRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Form {
            configurationSection
            modelsSection
        }
        .navigationTitle(model.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: .generalSave)) {
                    router.saveConfiguration(model)
                }
                .disabled(!model.canSaveConfiguration)
            }
        }
        .task {
            model.startInitialModelLoadIfNeeded()
        }
        .settingsAlert(alertBinding)
    }

    @ViewBuilder
    private var configurationSection: some View {
        if !model.configurationFields.isEmpty {
            Section(String(localized: .providerConfigurationSectionConfiguration)) {
                ForEach(model.configurationFields) { field in
                    ProviderConfigurationFieldRow(
                        field: field,
                        text: textBinding(for: field),
                        isOn: toggleBinding(for: field)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        if let modelSource = model.modelSource {
            Section {
                switch modelSource {
                case .remote, .`static`:
                    ForEach(model.provider.models, id: \.id) { providerModel in
                        ReadOnlyProviderModelRow(
                            title: model.title(for: providerModel),
                            subtitle: model.subtitle(for: providerModel)
                        )
                    }
                case .manual:
                    Button {
                        withAnimation(.default) {
                            model.appendManualModel()
                        }
                    } label: {
                        SettingsRowLabel(
                            title: String(localized: .providerConfigurationAddModel),
                            subtitle: model.manualModelsDetailText,
                            symbolName: "plus.circle",
                            tintColor: .systemBlue
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(Array(model.provider.models.enumerated()), id: \.offset) { index, _ in
                        LabeledContent(String(localized: .providerConfigurationModelId)) {
                            TextField(
                                LLMsProviderConfigurationModel.modelIDPlaceholder,
                                text: manualModelBinding(at: index)
                            )
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        }
                    }
                    .onDelete(perform: model.deleteManualModels)
                }
            } header: {
                providerModelsHeader(for: modelSource)
            } footer: {
                if let detail = model.modelRefreshDetailText {
                    Text(detail)
                }
            }
        }
    }

    @ViewBuilder
    private func providerModelsHeader(for modelSource: LLMsProviderModelSource) -> some View {
        if modelSource == .remote {
            HStack {
                Text(String(localized: .providerConfigurationSectionModels))
                Spacer()
                Button {
                    model.refreshModels()
                } label: {
                    if model.isLoadingModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: .providerConfigurationRefresh))
                    }
                }
                .disabled(model.isLoadingModels)
                .accessibilityLabel(String(localized: .providerConfigurationRefreshModels))
                .accessibilityValue(model.isLoadingModels ? String(localized: .providerConfigurationRefreshing) : "")
            }
        } else {
            Text(String(localized: .providerConfigurationSectionModels))
        }
    }

    private func textBinding(for field: LLMsProviderConfigurationField) -> Binding<String> {
        Binding {
            model.value(for: field)
        } set: { text in
            model.setValue(text, for: field)
        }
    }

    private func toggleBinding(for field: LLMsProviderConfigurationField) -> Binding<Bool> {
        Binding {
            model.booleanValue(for: field)
        } set: { isEnabled in
            model.setValue(isEnabled ? "true" : "false", for: field)
        }
    }

    private func manualModelBinding(at index: Int) -> Binding<String> {
        Binding {
            model.manualModelID(at: index)
        } set: { text in
            model.setManualModelID(text, at: index)
        }
    }

    private var alertBinding: Binding<SettingsAlert?> {
        Binding {
            model.alert
        } set: { alert in
            model.alert = alert
        }
    }
}

private struct ProviderConfigurationFieldRow: View {
    let field: LLMsProviderConfigurationField
    let text: Binding<String>
    let isOn: Binding<Bool>

    var body: some View {
        switch field.inputKind {
        case .toggle:
            Toggle(field.title, isOn: isOn)
        case .secret:
            LabeledContent(field.title) {
                SecureField(field.placeholder, text: text)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }
        case .plain, .url:
            LabeledContent(field.title) {
                TextField(field.placeholder, text: text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }
        }
    }

    private var keyboardType: UIKeyboardType {
        switch field.inputKind {
        case .plain:
            return .default
        case .secret:
            return .asciiCapable
        case .url:
            return .URL
        case .toggle:
            return .default
        }
    }

    private var textContentType: UITextContentType? {
        switch field.inputKind {
        case .plain:
            return .name
        case .secret:
            return .password
        case .url:
            return .URL
        case .toggle:
            return nil
        }
    }
}

private struct ReadOnlyProviderModelRow: View {
    let title: String
    let subtitle: String?

    var body: some View {
        SettingsRowLabel(
            title: title,
            subtitle: subtitle,
            symbolName: "cpu",
            tintColor: .secondaryLabel
        )
    }
}

@MainActor
private final class LLMsProviderConfigurationRouter {
    weak var hostViewController: UIViewController?

    func saveConfiguration(_ model: LLMsProviderConfigurationModel) {
        hostViewController?.view.endEditing(true)
        guard model.saveConfiguration() else {
            return
        }

        hostViewController?.navigationController?.popViewController(animated: true)
    }
}

@MainActor
@Observable
private final class LLMsProviderConfigurationModel {
    static let modelIDPlaceholder = "gpt-4.1-mini"

    @ObservationIgnored private let dependencies: AppDependencyContainer
    @ObservationIgnored private let updatedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var savedProvider: LLMsProviderRecord
    private var isNewProvider: Bool
    private var didStartInitialModelLoad = false

    var provider: LLMsProviderRecord
    var isLoadingModels = false
    var alert: SettingsAlert?

    init(
        provider: LLMsProviderRecord,
        dependencies: AppDependencyContainer,
        isNewProvider: Bool
    ) {
        self.provider = provider
        savedProvider = provider
        self.isNewProvider = isNewProvider
        self.dependencies = dependencies
    }

    var navigationTitle: String {
        dependencies.providerManager.displayName(for: provider)
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        dependencies.providerManager.configurationFields(for: provider.kind)
    }

    var modelSource: LLMsProviderModelSource? {
        dependencies.providerManager.modelSource(for: provider.kind)
    }

    var modelRefreshDetailText: String? {
        guard let updatedAt = provider.modelsUpdatedAt else {
            return nil
        }

        return String(localized: .generalUpdatedFormat(updatedDateFormatter.string(from: updatedAt)))
    }

    var manualModelsDetailText: String? {
        let modelCount = manualModelCount
        guard modelCount > 0 else {
            return nil
        }

        return modelCount == 1
            ? String(localized: .providerConfigurationModelCountOne)
            : String(localized: .providerConfigurationModelCountFormat(modelCount))
    }

    var canSaveConfiguration: Bool {
        hasRequiredConfigurationFields && (isNewProvider || hasUnsavedChanges)
    }

    func value(for field: LLMsProviderConfigurationField) -> String {
        provider.configurationValue(for: field.binding)
    }

    func booleanValue(for field: LLMsProviderConfigurationField) -> Bool {
        let normalizedValue = value(for: field)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["true", "1", "yes", "on"].contains(normalizedValue)
    }

    func setValue(_ text: String, for field: LLMsProviderConfigurationField) {
        provider.setConfigurationValue(text, for: field.binding)
    }

    func manualModelID(at index: Int) -> String {
        guard provider.models.indices.contains(index) else {
            return ""
        }

        return provider.models[index].id
    }

    func setManualModelID(_ text: String, at index: Int) {
        guard provider.models.indices.contains(index) else {
            return
        }

        provider.models[index].id = text
        provider.models[index].name = normalizedModelName(provider.models[index].name)
    }

    func appendManualModel() {
        provider.models.append(
            LLMsProviderModel(
                id: "",
                name: nil,
                contextLength: nil
            )
        )
    }

    func deleteManualModels(at offsets: IndexSet) {
        provider.models.remove(atOffsets: offsets)
    }

    func title(for model: LLMsProviderModel) -> String {
        normalizedModelName(model.name) ?? model.id
    }

    func subtitle(for model: LLMsProviderModel) -> String? {
        normalizedModelName(model.name) == nil ? nil : model.id
    }

    func startInitialModelLoadIfNeeded() {
        guard modelSource == .remote,
              !isNewProvider,
              !didStartInitialModelLoad else {
            return
        }

        didStartInitialModelLoad = true
        refreshModels()
    }

    func refreshModels() {
        guard modelSource == .remote,
              !isLoadingModels else {
            return
        }

        isLoadingModels = true

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let models = try await dependencies.providerManager.fetchModels(for: provider)
                let modelsUpdatedAt = Date()
                provider.models = models
                provider.modelsUpdatedAt = modelsUpdatedAt
                savedProvider.models = models
                savedProvider.modelsUpdatedAt = modelsUpdatedAt
                if !isNewProvider {
                    dependencies.providerStore.updateProviderModels(
                        id: provider.id,
                        models: models,
                        modelsUpdatedAt: modelsUpdatedAt
                    )
                }
            } catch {
                alert = SettingsAlert(
                    title: String(localized: .providerConfigurationErrorUnableToRefreshModels),
                    message: error.localizedDescription
                )
            }

            isLoadingModels = false
        }
    }

    func saveConfiguration() -> Bool {
        provider = providerForSaving
        dependencies.providerStore.saveProvider(provider)
        isNewProvider = false
        savedProvider = provider
        return true
    }

    private var manualModelCount: Int {
        provider.models
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private var hasRequiredConfigurationFields: Bool {
        dependencies.providerManager.hasRequiredConfigurationFields(for: provider)
    }

    private var hasUnsavedChanges: Bool {
        providerForComparison(provider) != providerForComparison(savedProvider)
    }

    private var providerForSaving: LLMsProviderRecord {
        var normalizedRecord = normalizedProvider(provider)
        guard hasManualModelListChanges else {
            return normalizedRecord
        }

        normalizedRecord.modelsUpdatedAt = Date()
        return normalizedRecord
    }

    private func normalizedProvider(_ provider: LLMsProviderRecord) -> LLMsProviderRecord {
        var normalizedRecord = provider
        normalizedRecord.models = provider.models.compactMap { model in
            let trimmedID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                return nil
            }

            return LLMsProviderModel(
                id: trimmedID,
                name: normalizedModelName(model.name),
                contextLength: model.contextLength,
                reasoningEfforts: model.reasoningEfforts
            )
        }
        return normalizedRecord
    }

    private func providerForComparison(_ provider: LLMsProviderRecord) -> LLMsProviderRecord {
        var normalizedRecord = normalizedProvider(provider)
        if modelSource == .manual {
            normalizedRecord.modelsUpdatedAt = normalizedProvider(savedProvider).modelsUpdatedAt
        }
        return normalizedRecord
    }

    private var hasManualModelListChanges: Bool {
        guard modelSource == .manual else {
            return false
        }

        return normalizedProvider(provider).models != normalizedProvider(savedProvider).models
    }

    private func normalizedModelName(_ name: String?) -> String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
