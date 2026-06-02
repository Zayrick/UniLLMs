//
//  MCPServerRecordTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class MCPServerRecordTests: XCTestCase {
    @MainActor
    func testDisplayNameUsesTrimmedNameWhenPresent() {
        let server = MCPServerRecord(
            name: "  Team Tools  ",
            configuration: MCPServerConfiguration(endpoint: "https://example.com/mcp")
        )

        XCTAssertEqual(server.displayName, "Team Tools")
    }

    @MainActor
    func testDisplayNameFallsBackToEndpointHost() {
        let server = MCPServerRecord(
            name: " ",
            configuration: MCPServerConfiguration(endpoint: "https://tools.example.com/mcp")
        )

        XCTAssertEqual(server.displayName, "tools.example.com")
    }

    @MainActor
    func testDisplayNameFallsBackToGenericNameWhenNameAndEndpointAreEmpty() {
        let server = MCPServerRecord(name: "", configuration: MCPServerConfiguration(endpoint: ""))

        XCTAssertEqual(server.displayName, "MCP Server")
    }
}
