//
//  ToolsViewController.swift
//  UniLLMs
//
//  Displays tool-call settings, built-in tools, and configured MCP servers.
//  Created by Zayrick on 2026/5/15.
//

import Observation
import SwiftUI
import UIKit

final class ToolsViewController: UIHostingController<ToolsSettingsForm> {
    private let model: ToolsSettingsModel
    private let router: ToolsSettingsRouter

    init(dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies) {
        let model = ToolsSettingsModel(dependencies: dependencies)
        let router = ToolsSettingsRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(rootView: ToolsSettingsForm(model: model, router: router))
        router.hostViewController = self
    }

    @MainActor
    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        let model = ToolsSettingsModel(dependencies: dependencies)
        let router = ToolsSettingsRouter(dependencies: dependencies)
        self.model = model
        self.router = router
        super.init(coder: coder, rootView: ToolsSettingsForm(model: model, router: router))
        router.hostViewController = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshContent()
    }
}

struct ToolsSettingsForm: View {
    private let model: ToolsSettingsModel
    private let router: ToolsSettingsRouter

    fileprivate init(
        model: ToolsSettingsModel,
        router: ToolsSettingsRouter
    ) {
        self.model = model
        self.router = router
    }

    var body: some View {
        Form {
            masterSwitchSection
            systemToolsSection
            groupedToolsSection(.calendar)
            groupedToolsSection(.memory)
            mcpServersSection
        }
        .navigationTitle(String(localized: .settingsRowToolsTitle))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.servers.count > 1 {
                    EditButton()
                }

                Button(action: router.addMCPServer) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: .generalAdd))
            }
        }
    }

    private var masterSwitchSection: some View {
        Section {
            Toggle(isOn: toolsEnabledBinding) {
                ToolRowLabel(
                    title: String(localized: .toolsEnableTools),
                    subtitle: nil,
                    symbolName: "hammer",
                    isEnabled: model.isToolsEnabled
                )
            }
        }
    }

    @ViewBuilder
    private var systemToolsSection: some View {
        if !model.systemTools.isEmpty {
            Section(String(localized: .toolsSectionSystem)) {
                ForEach(model.systemTools) { tool in
                    ToolToggleRow(
                        title: tool.presentationName,
                        subtitle: nil,
                        symbolName: tool.symbolName ?? "wrench.and.screwdriver",
                        isEnabled: model.isBuiltInToolEnabled(id: tool.id)
                    ) { isEnabled in
                        model.setBuiltInTool(id: tool.id, isEnabled: isEnabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupedToolsSection(_ group: ToolsSettingsGroup) -> some View {
        if model.isToolGroupAvailable(group) {
            Section(group.sectionTitle) {
                Toggle(isOn: groupBinding(for: group)) {
                    ToolRowLabel(
                        title: group.title,
                        subtitle: model.isToolGroupEnabled(group) ? model.enabledCountSummary(for: group) : nil,
                        symbolName: group.symbolName,
                        isEnabled: model.isToolGroupEnabled(group)
                    )
                }

                if model.isToolGroupEnabled(group) {
                    ToolNavigationRow(
                        title: group.listTitle,
                        subtitle: group.detailText,
                        symbolName: group.listSymbolName,
                        isEnabled: true
                    ) {
                        router.showToolGroup(group, model: model)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.default, value: model.isToolGroupEnabled(group))
        }
    }

    private var mcpServersSection: some View {
        Section {
            ForEach(model.servers) { server in
                MCPServerRow(server: server) {
                    router.editMCPServer(server)
                }
            }
            .onDelete(perform: model.deleteServers)
            .onMove(perform: model.moveServers)
        } header: {
            Text("MCP")
        } footer: {
            if model.servers.isEmpty {
                Text(String(localized: .toolsFooterNoMcpServers))
            }
        }
    }

    private var toolsEnabledBinding: Binding<Bool> {
        Binding {
            model.isToolsEnabled
        } set: { isEnabled in
            model.setToolsEnabled(isEnabled)
        }
    }

    private func groupBinding(for group: ToolsSettingsGroup) -> Binding<Bool> {
        Binding {
            model.isToolGroupEnabled(group)
        } set: { isEnabled in
            withAnimation(.default) {
                model.setToolGroup(group, isEnabled: isEnabled)
            }
        }
    }
}

private struct ToolGroupSettingsForm: View {
    let group: ToolsSettingsGroup
    let model: ToolsSettingsModel

    var body: some View {
        Form {
            Section {
                switch group {
                case .calendar:
                    ForEach(model.calendarTools) { tool in
                        ToolToggleRow(
                            title: tool.presentationName,
                            subtitle: tool.summary,
                            symbolName: tool.symbolName ?? group.symbolName,
                            isEnabled: model.isBuiltInToolEnabled(id: tool.id)
                        ) { isEnabled in
                            model.setBuiltInTool(id: tool.id, isEnabled: isEnabled)
                        }
                    }
                case .memory:
                    ForEach(model.memoryToolItems, id: \.id) { item in
                        ToolToggleRow(
                            title: item.title,
                            subtitle: model.summaryForBuiltInTool(id: item.id),
                            symbolName: item.symbolName,
                            isEnabled: model.isBuiltInToolEnabled(id: item.id)
                        ) { isEnabled in
                            model.setBuiltInTool(id: item.id, isEnabled: isEnabled)
                        }
                    }
                }
            }

            Section {
                Toggle(isOn: approvalSkippedBinding) {
                    ToolRowLabel(
                        title: String(localized: "tools.approval.skip_title"),
                        subtitle: group.approvalSkipDetail,
                        symbolName: "checkmark.shield",
                        isEnabled: model.isApprovalSkipped(for: group)
                    )
                }
            }
        }
        .navigationTitle(group.listTitle)
    }

    private var approvalSkippedBinding: Binding<Bool> {
        Binding {
            model.isApprovalSkipped(for: group)
        } set: { isSkipped in
            model.setApprovalSkipped(isSkipped, for: group)
        }
    }
}

private struct ToolToggleRow: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: binding) {
            ToolRowLabel(
                title: title,
                subtitle: subtitle,
                symbolName: symbolName,
                isEnabled: isEnabled
            )
        }
    }

    private var binding: Binding<Bool> {
        Binding {
            isEnabled
        } set: { newValue in
            onToggle(newValue)
        }
    }
}

private struct ToolNavigationRow: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ToolRowLabel(
                    title: title,
                    subtitle: subtitle,
                    symbolName: symbolName,
                    isEnabled: isEnabled
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

private struct MCPServerRow: View {
    let server: MCPServerRecord
    let action: () -> Void

    var body: some View {
        ToolNavigationRow(
            title: server.displayName,
            subtitle: serverSubtitle,
            symbolName: "server.rack",
            isEnabled: server.configuration.isEnabled,
            action: action
        )
    }

    private var serverSubtitle: String? {
        let endpoint = server.configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.isEmpty ? nil : endpoint
    }
}

private struct ToolRowLabel: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isEnabled: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(Color(uiColor: isEnabled ? .systemGreen : .secondaryLabel))
        }
    }
}

@MainActor
private final class ToolsSettingsRouter {
    weak var hostViewController: UIViewController?

    private let dependencies: AppDependencyContainer

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
    }

    func addMCPServer() {
        let server = dependencies.mcpServerManager.makeServerDraft()
        hostViewController?.navigationController?.pushViewController(
            MCPServerConfigurationViewController(
                server: server,
                dependencies: dependencies,
                isNewServer: true
            ),
            animated: true
        )
    }

    func editMCPServer(_ server: MCPServerRecord) {
        hostViewController?.navigationController?.pushViewController(
            MCPServerConfigurationViewController(
                server: server,
                dependencies: dependencies
            ),
            animated: true
        )
    }

    func showToolGroup(_ group: ToolsSettingsGroup, model: ToolsSettingsModel) {
        let controller = UIHostingController(
            rootView: ToolGroupSettingsForm(group: group, model: model)
        )
        controller.title = group.listTitle
        hostViewController?.navigationController?.pushViewController(controller, animated: true)
    }
}

@MainActor
@Observable
private final class ToolsSettingsModel {
    @ObservationIgnored private let dependencies: AppDependencyContainer
    @ObservationIgnored private var toolSettingsObservation: NSObjectProtocol?
    @ObservationIgnored private var mcpServerObservation: NSObjectProtocol?

    var isToolsEnabled = false
    var systemTools: [ToolDefinition] = []
    var calendarTools: [ToolDefinition] = []
    var memoryToolItems: [MemoryToolUserFacingItem] = []
    var servers: [MCPServerRecord] = []
    var enabledBuiltInToolIDs: Set<String> = []
    var approvalSkippedToolIDs: Set<String> = []

    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        installStoreObservers()
        refreshContent()
    }

    deinit {
        if let toolSettingsObservation {
            NotificationCenter.default.removeObserver(toolSettingsObservation)
        }
        if let mcpServerObservation {
            NotificationCenter.default.removeObserver(mcpServerObservation)
        }
    }

    func refreshContent() {
        let builtInTools = dependencies.toolSettingsManager.registeredBuiltInTools()
        let builtInToolsByID = Dictionary(uniqueKeysWithValues: builtInTools.map { ($0.id, $0) })
        systemTools = builtInTools.filter {
            !CalendarToolCatalog.containsTool(id: $0.id)
                && !MemoryToolCatalog.containsTool(id: $0.id)
        }
        calendarTools = CalendarToolCatalog.toolIDs.compactMap {
            builtInToolsByID[$0]
        }

        let registeredToolIDs = Set(builtInTools.map(\.id))
        memoryToolItems = MemoryToolCatalog.userFacingItems.filter {
            registeredToolIDs.contains($0.id)
        }

        refreshToolSettings()
        refreshServers()
    }

    func setToolsEnabled(_ isEnabled: Bool) {
        dependencies.toolSettingsManager.isToolsEnabled = isEnabled
        refreshToolSettings()
    }

    func isBuiltInToolEnabled(id: String) -> Bool {
        enabledBuiltInToolIDs.contains(id)
    }

    func setBuiltInTool(id: String, isEnabled: Bool) {
        dependencies.toolSettingsManager.setBuiltInTool(id: id, isEnabled: isEnabled)
        refreshToolSettings()
    }

    func isApprovalSkipped(for group: ToolsSettingsGroup) -> Bool {
        let ids = toolIDs(for: group)
        return !ids.isEmpty && ids.allSatisfy { approvalSkippedToolIDs.contains($0) }
    }

    func setApprovalSkipped(_ isSkipped: Bool, for group: ToolsSettingsGroup) {
        dependencies.toolSettingsManager.setApprovalSkipped(isSkipped, forToolIDs: toolIDs(for: group))
        refreshToolSettings()
    }

    func isToolGroupAvailable(_ group: ToolsSettingsGroup) -> Bool {
        !toolIDs(for: group).isEmpty
    }

    func isToolGroupEnabled(_ group: ToolsSettingsGroup) -> Bool {
        enabledToolCount(for: group) > 0
    }

    func enabledCountSummary(for group: ToolsSettingsGroup) -> String {
        let ids = toolIDs(for: group)
        return enabledCountSummary(
            enabledCount: enabledToolCount(for: group),
            totalCount: ids.count
        )
    }

    func setToolGroup(_ group: ToolsSettingsGroup, isEnabled: Bool) {
        dependencies.toolSettingsManager.setBuiltInTools(
            ids: toolIDs(for: group),
            isEnabled: isEnabled
        )
        refreshToolSettings()
    }

    func summaryForBuiltInTool(id: String) -> String? {
        allBuiltInTools.first { $0.id == id }?.summary
    }

    func deleteServers(at offsets: IndexSet) {
        let deletedIDs = Set(
            offsets.compactMap { index in
                servers.indices.contains(index) ? servers[index].id : nil
            }
        )
        guard !deletedIDs.isEmpty else {
            return
        }

        servers.removeAll {
            deletedIDs.contains($0.id)
        }
        deletedIDs.forEach(dependencies.mcpServerManager.deleteServer)
        refreshServers()
    }

    func moveServers(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else {
            return
        }

        let previousServers = servers
        servers.move(fromOffsets: source, toOffset: destination)
        persistServerOrder(from: previousServers, to: servers)
        refreshServers()
    }

    private func installStoreObservers() {
        toolSettingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsToolSettingsStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshToolSettings()
            }
        }

        mcpServerObservation = NotificationCenter.default.addObserver(
            forName: UserDefaultsMCPServerStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshServers()
            }
        }
    }

    private func refreshToolSettings() {
        isToolsEnabled = dependencies.toolSettingsManager.isToolsEnabled
        enabledBuiltInToolIDs = Set(
            allBuiltInTools
                .filter { dependencies.toolSettingsManager.isBuiltInToolEnabled(id: $0.id) }
                .map(\.id)
        )
        approvalSkippedToolIDs = dependencies.toolSettingsManager.approvalSkippedToolIDs()
    }

    private func refreshServers() {
        servers = dependencies.mcpServerManager.configuredServers()
    }

    private var allBuiltInTools: [ToolDefinition] {
        systemTools + calendarTools
            + memoryToolItems.compactMap { item in
                dependencies.toolSettingsManager.registeredBuiltInTools().first {
                    $0.id == item.id
                }
            }
    }

    private func toolIDs(for group: ToolsSettingsGroup) -> [String] {
        switch group {
        case .calendar:
            calendarTools.map(\.id)
        case .memory:
            memoryToolItems.map(\.id)
        }
    }

    private func enabledToolCount(for group: ToolsSettingsGroup) -> Int {
        toolIDs(for: group).filter {
            enabledBuiltInToolIDs.contains($0)
        }.count
    }

    private func enabledCountSummary(enabledCount: Int, totalCount: Int) -> String {
        String(
            format: NSLocalizedString("tools.enabled_count_format", comment: ""),
            locale: Locale.current,
            arguments: [enabledCount, totalCount]
        )
    }

    private func persistServerOrder(
        from previousServers: [MCPServerRecord],
        to reorderedServers: [MCPServerRecord]
    ) {
        var workingServers = previousServers
        for targetIndex in reorderedServers.indices {
            let desiredID = reorderedServers[targetIndex].id
            guard let currentIndex = workingServers.firstIndex(where: { $0.id == desiredID }),
                  currentIndex != targetIndex else {
                continue
            }

            dependencies.mcpServerManager.moveServer(
                from: currentIndex,
                to: targetIndex
            )
            let movedServer = workingServers.remove(at: currentIndex)
            workingServers.insert(movedServer, at: targetIndex)
        }
    }
}

private enum ToolsSettingsGroup {
    case calendar
    case memory

    var title: String {
        switch self {
        case .calendar:
            return String(localized: "tools.calendar_tools")
        case .memory:
            return String(localized: "tools.memory_tools")
        }
    }

    var sectionTitle: String {
        switch self {
        case .calendar:
            return String(localized: "tools.section.calendar")
        case .memory:
            return String(localized: .toolsSectionMemory)
        }
    }

    var listTitle: String {
        switch self {
        case .calendar:
            return String(localized: "tools.calendar_tools.list")
        case .memory:
            return String(localized: "tools.memory_tools.list")
        }
    }

    var detailText: String {
        switch self {
        case .calendar:
            return String(localized: "tools.calendar_tools.detail")
        case .memory:
            return String(localized: "tools.memory_tools.detail")
        }
    }

    var symbolName: String {
        switch self {
        case .calendar:
            return "calendar"
        case .memory:
            return "brain.head.profile"
        }
    }

    var listSymbolName: String {
        switch self {
        case .calendar:
            return "calendar.badge.clock"
        case .memory:
            return "brain.head.profile"
        }
    }

    var approvalSkipDetail: String {
        switch self {
        case .calendar:
            return String(localized: "tools.approval.calendar_skip_detail")
        case .memory:
            return String(localized: "tools.approval.memory_skip_detail")
        }
    }
}
