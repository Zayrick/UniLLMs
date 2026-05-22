//
//  ChatContextBuilderTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class ChatContextBuilderTests: XCTestCase {
    func testBuildContextLoadsToolsBeforeRetrievingMemories() async {
        let session = ChatSession(title: "Session")
        let messages = [ChatMessage(role: .user, content: "Remember this.")]
        let memory = MemoryRecord(scope: .user, text: "Existing memory")
        let retriever = RecordingMemoryRetriever(result: [memory])
        let dynamicSource = RecordingDynamicToolSource(tools: [
            ContextBuilderTool(name: "lookup", displayName: "Lookup")
        ])
        let builder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: retriever),
            toolCatalog: ToolCatalog(
                registry: ToolRegistry(tools: []),
                isEnabled: { true },
                dynamicSources: [dynamicSource]
            )
        )

        let context = await builder.buildContext(
            session: session,
            messages: messages,
            systemPrompt: nil,
            includeTools: true
        )

        XCTAssertEqual(context.session, session)
        XCTAssertEqual(context.messages, messages)
        XCTAssertEqual(context.memories, [memory])
        XCTAssertEqual(context.availableTools.map(\.name), ["lookup"])
        XCTAssertEqual(retriever.capturedContexts.first?.availableTools.map(\.name), ["lookup"])
        XCTAssertEqual(dynamicSource.loadCallCount, 1)
    }

    func testBuildContextSkipsToolLoadingWhenToolsAreExcluded() async {
        let retriever = RecordingMemoryRetriever(result: [])
        let dynamicSource = RecordingDynamicToolSource(tools: [
            ContextBuilderTool(name: "lookup", displayName: "Lookup")
        ])
        let builder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: retriever),
            toolCatalog: ToolCatalog(
                registry: ToolRegistry(tools: []),
                isEnabled: { true },
                dynamicSources: [dynamicSource]
            )
        )

        let context = await builder.buildContext(
            session: nil,
            messages: [],
            systemPrompt: nil,
            includeTools: false
        )

        XCTAssertTrue(context.availableTools.isEmpty)
        XCTAssertTrue(retriever.capturedContexts.first?.availableTools.isEmpty == true)
        XCTAssertEqual(dynamicSource.loadCallCount, 0)
    }

    func testBuildContextFallsBackToEmptyMemoriesWhenRetrieverFails() async {
        let retriever = RecordingMemoryRetriever(error: TestMemoryError.failed)
        let builder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: retriever),
            toolCatalog: ToolCatalog(registry: ToolRegistry(tools: []), isEnabled: { true })
        )

        let context = await builder.buildContext(
            session: nil,
            messages: [],
            systemPrompt: nil,
            includeTools: true
        )

        XCTAssertTrue(context.memories.isEmpty)
        XCTAssertEqual(retriever.capturedContexts.count, 1)
    }

    func testBuildContextIncludesSystemPromptForMemoryRetrievalAndResult() async {
        let prompt = SystemPromptRecord(
            title: "Translator",
            content: "Always answer in Chinese."
        )
        let retriever = RecordingMemoryRetriever(result: [])
        let builder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: retriever),
            toolCatalog: ToolCatalog(registry: ToolRegistry(tools: []), isEnabled: { true })
        )

        let context = await builder.buildContext(
            session: nil,
            messages: [],
            systemPrompt: prompt,
            includeTools: false
        )

        XCTAssertEqual(context.systemPrompt, prompt)
        XCTAssertEqual(retriever.capturedContexts.first?.systemPrompt, prompt)
    }
}

private enum TestMemoryError: Error {
    case failed
}

private final class RecordingMemoryRetriever: MemoryRetriever {
    private let result: [MemoryRecord]
    private let error: Error?
    private(set) var capturedContexts: [ChatContext] = []

    init(result: [MemoryRecord] = [], error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        capturedContexts.append(context)
        if let error {
            throw error
        }
        return result
    }
}

private final class RecordingDynamicToolSource: DynamicToolSource {
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

private struct ContextBuilderTool: Tool {
    let definition: ToolDefinition

    init(name: String, displayName: String) {
        definition = ToolDefinition(name: name, displayName: displayName, summary: "")
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, content: "")
    }
}
