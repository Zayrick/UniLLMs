//
//  ToolsCore.swift
//  UniLLMs
//
//  Tool protocol, registry, dynamic source contract, and the catalog/manager pair that resolves tools for chat turns.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct ToolDefinition: Codable, Equatable, Identifiable {
    var id: String {
        name
    }

    var name: String
    var displayName: String?
    var summary: String
    var symbolName: String?
    var parameters: JSONValue

    init(
        name: String,
        displayName: String? = nil,
        summary: String,
        symbolName: String? = nil,
        parameters: JSONValue = .emptyObjectSchema
    ) {
        self.name = name
        self.displayName = displayName
        self.summary = summary
        self.symbolName = symbolName
        self.parameters = parameters
    }

    var presentationName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? name : trimmed
    }
}

nonisolated struct ToolCall: Codable, Equatable, Identifiable {
    var id: String
    var toolID: String
    var arguments: [String: JSONValue]
}

nonisolated enum ToolExecutionStatus: String, Codable, Equatable {
    case success
    case error
}

nonisolated struct ToolResult: Codable, Equatable {
    var callID: String
    var content: String

    /// Semantic execution status from the tool layer.
    ///
    /// A tool can complete at the transport/protocol level while still
    /// reporting an execution error that should be visible to the model and UI.
    var status: ToolExecutionStatus

    init(
        callID: String,
        content: String,
        status: ToolExecutionStatus = .success
    ) {
        self.callID = callID
        self.content = content
        self.status = status
    }

    var isError: Bool {
        status == .error
    }
}

struct ToolExecutionContext {
    var session: ChatSession?
}

protocol Tool {
    var definition: ToolDefinition { get }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult
}

final class ToolRegistry {
    private var toolsByID: [String: any Tool] = [:]
    private var orderedToolIDs: [String] = []

    init(tools: [any Tool] = []) {
        tools.forEach(register)
    }

    func register(_ tool: any Tool) {
        let id = tool.definition.name
        if toolsByID[id] == nil {
            orderedToolIDs.append(id)
        }
        toolsByID[id] = tool
    }

    func tool(id: String) -> (any Tool)? {
        toolsByID[id]
    }

    var tools: [any Tool] {
        orderedToolIDs.compactMap {
            toolsByID[$0]
        }
    }
}

enum ToolManagerError: LocalizedError, Equatable {
    case missingTool(String)

    var errorDescription: String? {
        switch self {
        case let .missingTool(id):
            return String(localized: .toolsErrorMissingToolFormat(id))
        }
    }
}

protocol DynamicToolSource {
    func loadTools() async -> [any Tool]
}

/// Aggregates the static built-in `ToolRegistry` with tools loaded dynamically per turn (e.g. MCP servers).
/// Owns the resolution path used by `ToolManager`, so dynamic tools never leak into the static registry.
final class ToolCatalog {
    private let registry: ToolRegistry
    private let isEnabled: () -> Bool
    private let isRegisteredToolEnabled: (String) -> Bool
    private let dynamicSources: [any DynamicToolSource]
    private var dynamicToolsByID: [String: any Tool] = [:]

    init(
        registry: ToolRegistry,
        isEnabled: @escaping () -> Bool,
        isRegisteredToolEnabled: @escaping (String) -> Bool = { _ in true },
        dynamicSources: [any DynamicToolSource] = []
    ) {
        self.registry = registry
        self.isEnabled = isEnabled
        self.isRegisteredToolEnabled = isRegisteredToolEnabled
        self.dynamicSources = dynamicSources
    }

    func loadAvailableTools() async -> [ToolDefinition] {
        guard isEnabled() else {
            dynamicToolsByID = [:]
            return []
        }

        var dynamicTools: [String: any Tool] = [:]
        for source in dynamicSources {
            for tool in await source.loadTools() {
                dynamicTools[tool.definition.name] = tool
            }
        }
        dynamicToolsByID = dynamicTools

        let builtInDefinitions = registry.tools
            .filter { isRegisteredToolEnabled($0.definition.name) }
            .map(\.definition)
        let allDefinitions = builtInDefinitions + dynamicTools.values.map(\.definition)
        return allDefinitions.sorted {
            $0.presentationName.localizedCaseInsensitiveCompare($1.presentationName) == .orderedAscending
        }
    }

    func tool(id: String) -> (any Tool)? {
        guard isEnabled() else {
            return nil
        }

        if let tool = registry.tool(id: id),
           isRegisteredToolEnabled(id) {
            return tool
        }

        return dynamicToolsByID[id]
    }
}

final class ToolManager {
    private let catalog: ToolCatalog
    private let approvalManager: (any ToolApprovalManaging)?

    init(
        catalog: ToolCatalog,
        approvalManager: (any ToolApprovalManaging)? = nil
    ) {
        self.catalog = catalog
        self.approvalManager = approvalManager
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        try Task.checkCancellation()

        guard let tool = catalog.tool(id: call.toolID) else {
            throw ToolManagerError.missingTool(call.toolID)
        }

        if let approvalManager {
            switch try await approvalManager.requestApprovalIfNeeded(call: call, definition: tool.definition) {
            case .approved:
                break
            case .rejected:
                return ToolResult(
                    callID: call.id,
                    content: String(localized: "tools.approval.rejected"),
                    status: .error
                )
            }
        }

        try Task.checkCancellation()
        return try await tool.execute(call: call, context: context)
    }
}
