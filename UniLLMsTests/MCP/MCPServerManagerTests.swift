//
//  MCPServerManagerTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class MCPServerManagerTests: XCTestCase {
    @MainActor
    func testLoadToolsOnlyConnectsEnabledServers() async {
        let enabledServer = MCPServerRecord(
            name: "Enabled",
            configuration: MCPServerConfiguration(endpoint: "https://enabled.example/mcp", isEnabled: true)
        )
        let disabledServer = MCPServerRecord(
            name: "Disabled",
            configuration: MCPServerConfiguration(endpoint: "https://disabled.example/mcp", isEnabled: false)
        )
        let enabledClient = ManagerMCPClient(descriptors: [
            MCPToolDescriptor(
                originalName: "search",
                definition: ToolDefinition(name: "mcp_search", summary: "")
            )
        ])
        let disabledClient = ManagerMCPClient()
        let manager = MCPServerManager(
            store: InMemoryMCPServerStore(servers: [enabledServer, disabledServer]),
            clientFactory: { server in
                server.id == enabledServer.id ? enabledClient : disabledClient
            }
        )

        let tools = await manager.loadTools()

        XCTAssertEqual(tools.map { $0.definition.name }, ["mcp_search"])
        XCTAssertEqual(enabledClient.connectCallCount, 1)
        XCTAssertEqual(enabledClient.loadToolsCallCount, 1)
        XCTAssertEqual(disabledClient.connectCallCount, 0)
    }

    @MainActor
    func testLoadToolsSkipsFailingServerAndKeepsOtherServers() async {
        let failingServer = MCPServerRecord(name: "Failing")
        let workingServer = MCPServerRecord(name: "Working")
        let failingClient = ManagerMCPClient(error: TestMCPError.failed)
        let workingClient = ManagerMCPClient(descriptors: [
            MCPToolDescriptor(
                originalName: "lookup",
                definition: ToolDefinition(name: "mcp_lookup", summary: "")
            )
        ])
        let manager = MCPServerManager(
            store: InMemoryMCPServerStore(servers: [failingServer, workingServer]),
            clientFactory: { server in
                server.id == failingServer.id ? failingClient : workingClient
            }
        )

        let tools = await manager.loadTools()

        XCTAssertEqual(tools.map { $0.definition.name }, ["mcp_lookup"])
        XCTAssertEqual(failingClient.connectCallCount, 1)
        XCTAssertEqual(workingClient.connectCallCount, 1)
    }
}

private enum TestMCPError: Error {
    case failed
}

private final class ManagerMCPClient: MCPClient {
    private let descriptors: [MCPToolDescriptor]
    private let error: Error?
    private(set) var connectCallCount = 0
    private(set) var loadToolsCallCount = 0

    init(
        descriptors: [MCPToolDescriptor] = [],
        error: Error? = nil
    ) {
        self.descriptors = descriptors
        self.error = error
    }

    func connect() async throws {
        connectCallCount += 1
        if let error {
            throw error
        }
    }

    func loadTools() async throws -> [MCPToolDescriptor] {
        loadToolsCallCount += 1
        if let error {
            throw error
        }
        return descriptors
    }

    func callTool(originalName: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        MCPToolResult(content: "", isError: false)
    }
}

private final class InMemoryMCPServerStore: MCPServerStore {
    private var servers: [MCPServerRecord]

    init(servers: [MCPServerRecord]) {
        self.servers = servers
    }

    func loadServers() -> [MCPServerRecord] {
        servers
    }

    func makeServerDraft() -> MCPServerRecord {
        MCPServerRecord(name: "")
    }

    func saveServerRecord(_ server: MCPServerRecord) {
        servers.append(server)
    }

    func deleteServerRecord(id: UUID) {
        servers.removeAll { $0.id == id }
    }

    func moveServer(from sourceIndex: Int, to destinationIndex: Int) {}
}
