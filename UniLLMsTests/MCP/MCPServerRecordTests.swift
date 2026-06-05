//
//  MCPServerRecordTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class MCPServerRecordTests: XCTestCase {
    func testDisplayNameUsesTrimmedNameWhenPresent() {
        let server = MCPServerRecord(
            name: "  Team Tools  ",
            configuration: MCPServerConfiguration(endpoint: "https://example.com/mcp"),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(server.displayName, "Team Tools")
    }

    func testDisplayNameFallsBackToEndpointHost() {
        let server = MCPServerRecord(
            name: " ",
            configuration: MCPServerConfiguration(endpoint: "https://tools.example.com/mcp"),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(server.displayName, "tools.example.com")
    }

    func testDisplayNameFallsBackToGenericNameWhenNameAndEndpointAreEmpty() {
        let server = MCPServerRecord(
            name: "",
            configuration: MCPServerConfiguration(endpoint: ""),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(server.displayName, "MCP Server")
    }
}
