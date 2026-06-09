//
//  MCPServerConfigurationViewController.swift
//  UniLLMs
//
//  Hosts Streamable HTTP MCP server configuration.
//  Created by Zayrick on 2026/5/15.
//

import Observation
import SwiftUI
import UIKit

final class MCPServerConfigurationViewController: UIHostingController<MCPServerConfigurationForm> {
    private let model: MCPServerConfigurationModel
    private let router: MCPServerConfigurationRouter

    init(
        server: MCPServerRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewServer: Bool = false
    ) {
        let model = MCPServerConfigurationModel(
            server: server,
            dependencies: dependencies,
            isNewServer: isNewServer
        )
        let router = MCPServerConfigurationRouter()
        self.model = model
        self.router = router
        super.init(rootView: MCPServerConfigurationForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = MCPServerConfigurationModel(
            server: dependencies.mcpServerManager.makeServerDraft(),
            dependencies: dependencies,
            isNewServer: true
        )
        let router = MCPServerConfigurationRouter()
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: MCPServerConfigurationForm(model: model, router: router))
        router.hostViewController = self
    }
}

struct MCPServerConfigurationForm: View {
    private let model: MCPServerConfigurationModel
    private let router: MCPServerConfigurationRouter

    fileprivate init(
        model: MCPServerConfigurationModel,
        router: MCPServerConfigurationRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Form {
            availabilitySection
            metadataSection
            connectionSection
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
    }

    private var availabilitySection: some View {
        Section {
            Toggle(isOn: isServerEnabledBinding) {
                SettingsRowLabel(
                    title: String(localized: .mcpEnableServer),
                    symbolName: "power",
                    tintColor: model.isServerEnabled ? .systemGreen : .secondaryLabel
                )
            }
        }
    }

    private var metadataSection: some View {
        Section {
            LabeledContent(String(localized: .mcpName)) {
                TextField(String(localized: .mcpServer), text: nameTextBinding)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.name)
            }
        }
    }

    private var connectionSection: some View {
        Section(String(localized: .mcpConnection)) {
            LabeledContent(String(localized: .mcpEndpoint)) {
                TextField("https://example.com/mcp", text: endpointTextBinding)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            LabeledContent(String(localized: .mcpHeaders)) {
                TextField(#"{"Authorization":"Bearer token"}"#, text: headersTextBinding)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            LabeledContent(String(localized: .mcpTimeout)) {
                TextField("60", text: timeoutTextBinding)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }
        }
    }

    private var isServerEnabledBinding: Binding<Bool> {
        Binding {
            model.isServerEnabled
        } set: { isEnabled in
            model.isServerEnabled = isEnabled
        }
    }

    private var nameTextBinding: Binding<String> {
        Binding {
            model.nameText
        } set: { text in
            model.nameText = text
        }
    }

    private var endpointTextBinding: Binding<String> {
        Binding {
            model.endpointText
        } set: { text in
            model.endpointText = text
        }
    }

    private var headersTextBinding: Binding<String> {
        Binding {
            model.headersText
        } set: { text in
            model.headersText = text
        }
    }

    private var timeoutTextBinding: Binding<String> {
        Binding {
            model.timeoutText
        } set: { text in
            model.timeoutText = text
        }
    }
}

@MainActor
private final class MCPServerConfigurationRouter {
    weak var hostViewController: UIViewController?

    func saveConfiguration(_ model: MCPServerConfigurationModel) {
        hostViewController?.view.endEditing(true)
        guard model.saveConfiguration() else {
            return
        }

        hostViewController?.navigationController?.popViewController(animated: true)
    }
}

@MainActor
@Observable
private final class MCPServerConfigurationModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer

    private var server: MCPServerRecord
    private var savedServer: MCPServerRecord
    private var isNewServer: Bool

    var nameText: String
    var endpointText: String
    var headersText: String
    var timeoutText: String
    var isServerEnabled: Bool

    init(
        server: MCPServerRecord,
        dependencies: AppDependencyContainer,
        isNewServer: Bool
    ) {
        self.server = server
        savedServer = server
        self.isNewServer = isNewServer
        self.dependencies = dependencies
        nameText = server.name
        endpointText = server.configuration.endpoint
        headersText = Self.headersText(from: server.configuration.headers)
        timeoutText = Self.timeoutText(from: server.configuration.timeout)
        isServerEnabled = server.configuration.isEnabled
    }

    var navigationTitle: String {
        let trimmedText = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? server.displayName : trimmedText
    }

    var canSaveConfiguration: Bool {
        serverForSaving != nil && (isNewServer || hasUnsavedChanges)
    }

    func saveConfiguration() -> Bool {
        guard let serverForSaving else {
            return false
        }

        server = serverForSaving
        dependencies.mcpServerManager.saveServer(server)
        isNewServer = false
        savedServer = server
        return true
    }

    private var hasUnsavedChanges: Bool {
        guard let serverForSaving else {
            return true
        }

        return serverForSaving != savedServer
    }

    private var serverForSaving: MCPServerRecord? {
        let trimmedEndpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEndpoint(trimmedEndpoint),
              let headers = Self.parseHeaders(headersText),
              let timeout = Self.parseTimeout(timeoutText) else {
            return nil
        }

        var updatedServer = server
        updatedServer.name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedServer.configuration = MCPServerConfiguration(
            endpoint: trimmedEndpoint,
            headers: headers,
            timeout: timeout,
            isEnabled: isServerEnabled
        )
        return updatedServer
    }

    private static func isValidEndpoint(_ endpoint: String) -> Bool {
        guard let components = URLComponents(string: endpoint),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.query == nil,
              components.fragment == nil,
              components.url != nil else {
            return false
        }

        return true
    }

    private static func parseHeaders(_ text: String) -> [String: String]? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return [:]
        }

        guard let data = trimmedText.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func parseTimeout(_ text: String) -> TimeInterval? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timeout = TimeInterval(trimmedText),
              timeout > 0 else {
            return nil
        }

        return timeout
    }

    private static func headersText(from headers: [String: String]) -> String {
        guard !headers.isEmpty,
              let data = try? JSONEncoder().encode(headers),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }

        return text
    }

    private static func timeoutText(from timeout: TimeInterval) -> String {
        let roundedTimeout = timeout.rounded()
        if roundedTimeout == timeout {
            return String(Int(roundedTimeout))
        }

        return String(timeout)
    }
}
