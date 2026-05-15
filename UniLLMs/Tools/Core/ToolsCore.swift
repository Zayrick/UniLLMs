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
    var parameters: JSONValue

    init(
        name: String,
        displayName: String? = nil,
        summary: String,
        parameters: JSONValue = .emptyObjectSchema
    ) {
        self.name = name
        self.displayName = displayName
        self.summary = summary
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

nonisolated struct ToolResult: Codable, Equatable {
    var callID: String
    var content: String
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

    init(tools: [any Tool] = []) {
        tools.forEach(register)
    }

    func register(_ tool: any Tool) {
        toolsByID[tool.definition.name] = tool
    }

    func tool(id: String) -> (any Tool)? {
        toolsByID[id]
    }

    var tools: [any Tool] {
        Array(toolsByID.values)
    }
}

enum ToolManagerError: LocalizedError, Equatable {
    case missingTool(String)

    var errorDescription: String? {
        switch self {
        case let .missingTool(id):
            return "Tool is not available: \(id)"
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
    private let dynamicSources: [any DynamicToolSource]
    private var dynamicToolsByID: [String: any Tool] = [:]

    init(
        registry: ToolRegistry,
        isEnabled: @escaping () -> Bool,
        dynamicSources: [any DynamicToolSource] = []
    ) {
        self.registry = registry
        self.isEnabled = isEnabled
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

        let allDefinitions = registry.tools.map(\.definition) + dynamicTools.values.map(\.definition)
        return allDefinitions.sorted {
            $0.presentationName.localizedCaseInsensitiveCompare($1.presentationName) == .orderedAscending
        }
    }

    func tool(id: String) -> (any Tool)? {
        registry.tool(id: id) ?? dynamicToolsByID[id]
    }
}

final class ToolManager {
    private let catalog: ToolCatalog

    init(catalog: ToolCatalog) {
        self.catalog = catalog
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        guard let tool = catalog.tool(id: call.toolID) else {
            throw ToolManagerError.missingTool(call.toolID)
        }

        return try await tool.execute(call: call, context: context)
    }
}
