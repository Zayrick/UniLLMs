//
//  ToolRegistryTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class ToolRegistryTests: XCTestCase {
    func testRegisteringDuplicateToolReplacesImplementationWithoutDuplicatingOrder() {
        let original = RegistryTool(name: "lookup", displayName: "Lookup")
        let replacement = RegistryTool(name: "lookup", displayName: "Lookup Replacement")
        let registry = ToolRegistry(tools: [original])

        registry.register(replacement)

        XCTAssertEqual(registry.tools.map(\.definition.presentationName), ["Lookup Replacement"])
        XCTAssertEqual(registry.tool(id: "lookup")?.definition.displayName, "Lookup Replacement")
    }

    func testToolsPreserveFirstRegistrationOrder() {
        let registry = ToolRegistry(tools: [
            RegistryTool(name: "first", displayName: "First"),
            RegistryTool(name: "second", displayName: "Second")
        ])

        XCTAssertEqual(registry.tools.map(\.definition.name), ["first", "second"])
    }
}

private struct RegistryTool: Tool {
    let definition: ToolDefinition

    init(name: String, displayName: String) {
        definition = ToolDefinition(name: name, displayName: displayName, summary: "")
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, content: "")
    }
}
