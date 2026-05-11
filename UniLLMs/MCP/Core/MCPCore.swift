//
//  MCPCore.swift
//  UniLLMs
//
//  Defines MCP server, transport, client, and tool adapter protocol boundaries; currently an architectural placeholder for future MCP integration.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct MCPServerRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var configuration: MCPServerConfiguration

    init(id: UUID = UUID(), name: String, configuration: MCPServerConfiguration) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}

nonisolated struct MCPServerConfiguration: Codable, Equatable {
    var command: String
    var arguments: [String]
    var environment: [String: String]
}

protocol MCPTransport {
    func connect(configuration: MCPServerConfiguration) async throws
    func disconnect() async
}

protocol MCPClient {
    func loadToolDefinitions() async throws -> [ToolDefinition]
    func execute(call: ToolCall) async throws -> ToolResult
}

struct MCPToolAdapter: Tool {
    let definition: ToolDefinition
    let client: any MCPClient

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        try await client.execute(call: call)
    }
}

final class MCPServerRegistry {
    private var records: [MCPServerRecord] = []

    func replaceAll(_ records: [MCPServerRecord]) {
        self.records = records
    }

    func allServers() -> [MCPServerRecord] {
        records
    }
}

final class MCPServerManager {
    private let registry: MCPServerRegistry

    init(registry: MCPServerRegistry = MCPServerRegistry()) {
        self.registry = registry
    }

    func configuredServers() -> [MCPServerRecord] {
        registry.allServers()
    }
}
