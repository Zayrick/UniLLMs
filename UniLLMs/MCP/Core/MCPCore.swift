//
//  MCPCore.swift
//  UniLLMs
//
//  Defines MCP server, client, and tool adapter protocol boundaries for remote MCP integration.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct MCPServerRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var configuration: MCPServerConfiguration
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        configuration: MCPServerConfiguration = MCPServerConfiguration(),
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        if let host = URL(string: configuration.endpoint)?.host,
           !host.isEmpty {
            return host
        }

        return String(localized: .mcpServer)
    }
}

nonisolated struct MCPServerConfiguration: Codable, Equatable {
    var endpoint: String
    var headers: [String: String]
    var timeout: TimeInterval
    var isEnabled: Bool

    init(
        endpoint: String = "",
        headers: [String: String] = [:],
        timeout: TimeInterval = 60.0,
        isEnabled: Bool = true
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.timeout = timeout
        self.isEnabled = isEnabled
    }
}

/// A tool advertised by an MCP server, paired with the original (server-side) tool name.
struct MCPToolDescriptor: Equatable {
    let originalName: String
    let definition: ToolDefinition
}

struct MCPToolResult: Equatable {
    let content: String
    let isError: Bool
}

protocol MCPClient {
    func connect() async throws
    func loadTools() async throws -> [MCPToolDescriptor]
    func callTool(originalName: String, arguments: [String: JSONValue]) async throws -> MCPToolResult
}

struct MCPToolAdapter: Tool {
    let definition: ToolDefinition
    let originalName: String
    let client: any MCPClient

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        let result = try await client.callTool(originalName: originalName, arguments: call.arguments)
        return ToolResult(
            callID: call.id,
            content: result.content,
            status: result.isError ? .error : .success
        )
    }
}

final class MCPServerManager: DynamicToolSource {
    nonisolated static let mcpToolNamePrefix = "mcp_"

    private let store: any MCPServerStore
    private let clientFactory: (MCPServerRecord) -> any MCPClient
    private let clock: any AppClock

    init(
        store: any MCPServerStore = UserDefaultsMCPServerStore.shared,
        clientFactory: @escaping (MCPServerRecord) -> any MCPClient = { MCPHTTPClient(server: $0) },
        clock: any AppClock = SystemAppClock()
    ) {
        self.store = store
        self.clientFactory = clientFactory
        self.clock = clock
    }

    func configuredServers() -> [MCPServerRecord] {
        store.loadServers()
    }

    func makeServerDraft() -> MCPServerRecord {
        MCPServerRecord(name: "", createdAt: clock.now)
    }

    func saveServer(_ server: MCPServerRecord) {
        store.saveServerRecord(server)
    }

    func deleteServer(id: UUID) {
        store.deleteServerRecord(id: id)
    }

    func moveServer(from sourceIndex: Int, to destinationIndex: Int) {
        store.moveServer(from: sourceIndex, to: destinationIndex)
    }

    func loadTools() async -> [any Tool] {
        let enabledServers = configuredServers().filter(\.configuration.isEnabled)
        guard !enabledServers.isEmpty else {
            return []
        }

        var adapters: [MCPToolAdapter] = []
        for server in enabledServers {
            do {
                let client = clientFactory(server)
                try await client.connect()
                let descriptors = try await client.loadTools()
                for descriptor in descriptors {
                    adapters.append(
                        MCPToolAdapter(
                            definition: descriptor.definition,
                            originalName: descriptor.originalName,
                            client: client
                        )
                    )
                }
            } catch {
                continue
            }
        }

        return adapters.map { $0 as any Tool }
    }
}
