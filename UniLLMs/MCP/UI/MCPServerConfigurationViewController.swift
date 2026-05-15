//
//  MCPServerConfigurationViewController.swift
//  UniLLMs
//
//  Edits a Streamable HTTP MCP server configuration.
//  Created by Codex on 2026/5/15.
//

import UIKit

final class MCPServerConfigurationViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case availability
        case metadata
        case connection
    }

    private enum ConnectionRow: Int, CaseIterable {
        case endpoint
        case headers
        case timeout
    }

    private enum MetadataRow: Int, CaseIterable {
        case name
    }

    private let dependencies: AppDependencyContainer
    private var saveButtonItem: UIBarButtonItem?
    private var server: MCPServerRecord
    private var savedServer: MCPServerRecord
    private var isNewServer: Bool
    private var nameText: String
    private var endpointText: String
    private var headersText: String
    private var timeoutText: String
    private var isServerEnabled: Bool

    init(
        server: MCPServerRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewServer: Bool = false
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
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        self.dependencies = dependencies
        server = dependencies.mcpServerManager.makeServerDraft()
        savedServer = server
        isNewServer = true
        nameText = server.name
        endpointText = server.configuration.endpoint
        headersText = Self.headersText(from: server.configuration.headers)
        timeoutText = Self.timeoutText(from: server.configuration.timeout)
        isServerEnabled = server.configuration.isEnabled
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = server.displayName
        tableView.register(
            ProviderTextFieldCell.self,
            forCellReuseIdentifier: ProviderTextFieldCell.reuseIdentifier
        )
        configureSaveButton()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .availability:
            return 1
        case .connection:
            return ConnectionRow.allCases.count
        case .metadata:
            return MetadataRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            return nil
        }

        switch section {
        case .availability:
            return nil
        case .metadata:
            return nil
        case .connection:
            return "Connection"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .availability:
            return enabledCell()
        case .connection:
            return connectionCell(for: indexPath)
        case .metadata:
            return metadataCell(for: indexPath)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch section {
        case .availability:
            return
        case .connection, .metadata:
            (tableView.cellForRow(at: indexPath) as? ProviderTextFieldCell)?.activateTextField()
        }
    }

    private func enabledCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var contentConfiguration = cell.defaultContentConfiguration()
        contentConfiguration.text = "Enable Server"
        contentConfiguration.image = UIImage(systemName: "power")
        cell.contentConfiguration = contentConfiguration

        let toggle = UISwitch()
        toggle.isOn = isServerEnabled
        toggle.addTarget(self, action: #selector(toggleServer(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }

    private func connectionCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let row = ConnectionRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        switch row {
        case .endpoint:
            return textFieldCell(
                title: "Endpoint",
                text: endpointText,
                placeholder: "https://example.com/mcp",
                keyboardType: .URL,
                textContentType: .URL
            ) { [weak self] text in
                self?.endpointText = text
                self?.updateAfterFieldChange()
            }
        case .headers:
            return textFieldCell(
                title: "Headers",
                text: headersText,
                placeholder: #"{"Authorization":"Bearer token"}"#,
                keyboardType: .asciiCapable,
                textContentType: nil
            ) { [weak self] text in
                self?.headersText = text
                self?.updateAfterFieldChange()
            }
        case .timeout:
            return textFieldCell(
                title: "Timeout",
                text: timeoutText,
                placeholder: "60",
                keyboardType: .decimalPad,
                textContentType: nil
            ) { [weak self] text in
                self?.timeoutText = text
                self?.updateAfterFieldChange()
            }
        }
    }

    private func metadataCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let row = MetadataRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        switch row {
        case .name:
            return textFieldCell(
                title: "Name",
                text: nameText,
                placeholder: "MCP Server",
                keyboardType: .default,
                textContentType: .name
            ) { [weak self] text in
                self?.nameText = text
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.title = trimmedText.isEmpty ? self?.server.displayName : trimmedText
                self?.updateAfterFieldChange()
            }
        }
    }

    private func textFieldCell(
        title: String,
        text: String,
        placeholder: String,
        keyboardType: UIKeyboardType,
        textContentType: UITextContentType?,
        onChange: @escaping (String) -> Void
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderTextFieldCell.reuseIdentifier
        ) as? ProviderTextFieldCell else {
            return UITableViewCell()
        }

        cell.configure(
            title: title,
            text: text,
            placeholder: placeholder,
            isSecureTextEntry: false,
            keyboardType: keyboardType,
            textContentType: textContentType
        )
        cell.onTextChange = onChange
        return cell
    }

    @objc private func toggleServer(_ sender: UISwitch) {
        isServerEnabled = sender.isOn
        updateAfterFieldChange()
    }

    private func updateAfterFieldChange() {
        updateSaveButtonState()
    }

    private func configureSaveButton() {
        let saveItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveConfiguration)
        )
        saveButtonItem = saveItem
        updateSaveButtonState()
    }

    @objc private func saveConfiguration() {
        view.endEditing(true)
        guard let serverForSaving else {
            updateSaveButtonState()
            return
        }

        server = serverForSaving
        dependencies.mcpServerManager.saveServer(server)
        isNewServer = false
        savedServer = server
        title = server.displayName
        updateSaveButtonState()
        navigationController?.popViewController(animated: true)
    }

    private func updateSaveButtonState() {
        navigationItem.rightBarButtonItem = canSaveConfiguration ? saveButtonItem : nil
    }

    private var canSaveConfiguration: Bool {
        serverForSaving != nil && (isNewServer || hasUnsavedChanges)
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
