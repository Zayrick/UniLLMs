//
//  ToolCatalogTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ToolCatalogTests: XCTestCase {
    func testBuiltInToolCatalogRegistersDateTimeTool() {
        let registry = BuiltInToolCatalog.makeRegistry(
            memoryManager: MemoryManager(store: InMemoryMemoryStore())
        )

        XCTAssertNotNil(registry.tool(id: "current_datetime"))
        XCTAssertNotNil(registry.tool(id: "calendar_create"))
        XCTAssertNotNil(registry.tool(id: "calendar_read"))
        XCTAssertNotNil(registry.tool(id: "calendar_update"))
        XCTAssertNotNil(registry.tool(id: "calendar_delete"))
        XCTAssertNotNil(registry.tool(id: "memory_add"))
        XCTAssertNotNil(registry.tool(id: "memory_delete"))
        XCTAssertNotNil(registry.tool(id: "memory_list"))
        XCTAssertNotNil(registry.tool(id: "memory_search"))
        XCTAssertNotNil(registry.tool(id: "memory_update"))
        XCTAssertEqual(registry.tools.first?.definition.symbolName, "clock")
    }

    func testToolCatalogExposesBuiltInToolsWhenEnabled() async {
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { true }
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertEqual(definitions.map(\.name), ["current_datetime"])
        XCTAssertEqual(definitions.first?.presentationName, "Current Date and Time")
    }

    func testToolCatalogReturnsNoToolsWhenDisabled() async {
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { false }
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertTrue(definitions.isEmpty)
        XCTAssertNil(catalog.tool(id: "current_datetime"))
    }

    func testToolCatalogSkipsDisabledBuiltInTools() async {
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { true },
            isRegisteredToolEnabled: { $0 != "current_datetime" }
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertTrue(definitions.isEmpty)
        XCTAssertNil(catalog.tool(id: "current_datetime"))
    }

    func testToolCatalogMergesBuiltInAndDynamicToolsSortedByPresentationName() async {
        let dynamicTool = CatalogTool(name: "dynamic_lookup", displayName: "A Dynamic Lookup")
        let source = CatalogDynamicToolSource(tools: [dynamicTool])
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { true },
            dynamicSources: [source]
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertEqual(definitions.map(\.presentationName), [
            "A Dynamic Lookup",
            "Current Date and Time"
        ])
        XCTAssertEqual(catalog.tool(id: "dynamic_lookup")?.definition.name, "dynamic_lookup")
        XCTAssertEqual(source.loadCallCount, 1)
    }

    func testToolCatalogClearsDynamicToolCacheWhenGloballyDisabled() async {
        var isEnabled = true
        let source = CatalogDynamicToolSource(tools: [
            CatalogTool(name: "dynamic_lookup", displayName: "Dynamic Lookup")
        ])
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: []),
            isEnabled: { isEnabled },
            dynamicSources: [source]
        )

        let enabledDefinitions = await catalog.loadAvailableTools()

        XCTAssertEqual(enabledDefinitions.map(\.name), ["dynamic_lookup"])
        XCTAssertNotNil(catalog.tool(id: "dynamic_lookup"))

        isEnabled = false

        let disabledDefinitions = await catalog.loadAvailableTools()

        XCTAssertTrue(disabledDefinitions.isEmpty)
        XCTAssertNil(catalog.tool(id: "dynamic_lookup"))
    }

    func testToolCatalogDisabledBuiltInToolDoesNotHideDynamicTool() async {
        let dynamicTool = CatalogTool(name: "current_datetime", displayName: "Dynamic Current Time")
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { true },
            isRegisteredToolEnabled: { $0 != "current_datetime" },
            dynamicSources: [CatalogDynamicToolSource(tools: [dynamicTool])]
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertEqual(definitions.map(\.presentationName), ["Dynamic Current Time"])
        XCTAssertEqual(catalog.tool(id: "current_datetime")?.definition.displayName, "Dynamic Current Time")
    }
}

private final class CatalogDynamicToolSource: DynamicToolSource {
    private let tools: [any Tool]
    private(set) var loadCallCount = 0

    init(tools: [any Tool]) {
        self.tools = tools
    }

    func loadTools() async -> [any Tool] {
        loadCallCount += 1
        return tools
    }
}

private struct CatalogTool: Tool {
    let definition: ToolDefinition

    init(name: String, displayName: String) {
        definition = ToolDefinition(name: name, displayName: displayName, summary: "")
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, content: "")
    }
}

private final class InMemoryMemoryStore: MemoryStore {
    private var memories: [MemoryRecord] = []

    func fetchMemories(scope: MemoryScope?) async throws -> [MemoryRecord] {
        guard let scope else {
            return memories
        }

        return memories.filter {
            $0.scope == scope
        }
    }

    func saveMemory(_ memory: MemoryRecord) async throws {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.append(memory)
        }
    }

    func deleteMemory(id: UUID) async throws {
        memories.removeAll {
            $0.id == id
        }
    }

    func deleteMemories(scope: MemoryScope?) async throws {
        if let scope {
            memories.removeAll {
                $0.scope == scope
            }
        } else {
            memories = []
        }
    }
}
