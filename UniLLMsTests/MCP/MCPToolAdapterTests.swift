//
//  MCPToolAdapterTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class MCPToolAdapterTests: XCTestCase {
    func testExecuteMapsMCPErrorResultToToolErrorStatus() async throws {
        let client = ToolAdapterMCPClient(result: MCPToolResult(content: "Invalid input.", isError: true))
        let adapter = MCPToolAdapter(
            definition: ToolDefinition(name: "mcp_search", summary: ""),
            originalName: "search",
            client: client
        )
        let call = ToolCall(id: "call_1", toolID: "mcp_search", arguments: ["query": .string("weather")])

        let result = try await adapter.execute(call: call, context: ToolExecutionContext())

        XCTAssertEqual(result.callID, "call_1")
        XCTAssertEqual(result.content, "Invalid input.")
        XCTAssertEqual(result.status, .error)
        XCTAssertEqual(client.capturedOriginalNames, ["search"])
        XCTAssertEqual(client.capturedArguments, [["query": .string("weather")]])
    }
}

private final class ToolAdapterMCPClient: MCPClient {
    private let result: MCPToolResult
    private(set) var capturedOriginalNames: [String] = []
    private(set) var capturedArguments: [[String: JSONValue]] = []

    init(result: MCPToolResult) {
        self.result = result
    }

    func connect() async throws {}

    func loadTools() async throws -> [MCPToolDescriptor] {
        []
    }

    func callTool(originalName: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        capturedOriginalNames.append(originalName)
        capturedArguments.append(arguments)
        return result
    }
}
