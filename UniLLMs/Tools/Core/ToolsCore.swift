//
//  ToolsCore.swift
//  UniLLMs
//
//  Defines tools, tool calls, results, registry, and manager; currently the protocol boundary for unified built-in and MCP tool integration.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct ToolDefinition: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var parameters: ToolParameterSchema
}

nonisolated struct ToolParameterSchema: Codable, Equatable {
    var properties: [String: String]
    var required: [String]

    static let empty = ToolParameterSchema(properties: [:], required: [])
}

nonisolated struct ToolCall: Codable, Equatable, Identifiable {
    var id: String
    var toolID: String
    var arguments: [String: String]
}

nonisolated struct ToolResult: Codable, Equatable {
    var callID: String
    var content: String
}

struct ToolExecutionContext {
    var session: ChatSession?
    var requestPermission: ((ToolDefinition) async -> Bool)?
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
        toolsByID[tool.definition.id] = tool
    }

    func tool(id: String) -> (any Tool)? {
        toolsByID[id]
    }

    var definitions: [ToolDefinition] {
        toolsByID.values.map(\.definition).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

enum ToolManagerError: LocalizedError, Equatable {
    case missingTool(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case let .missingTool(id):
            return "Tool is not available: \(id)"
        case let .permissionDenied(name):
            return "Permission denied for tool: \(name)"
        }
    }
}

final class ToolManager {
    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        guard let tool = registry.tool(id: call.toolID) else {
            throw ToolManagerError.missingTool(call.toolID)
        }

        if let requestPermission = context.requestPermission,
           await !requestPermission(tool.definition) {
            throw ToolManagerError.permissionDenied(tool.definition.name)
        }

        return try await tool.execute(call: call, context: context)
    }
}
