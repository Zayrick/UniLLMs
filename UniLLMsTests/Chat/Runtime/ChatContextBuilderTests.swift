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
        let session = makeTestChatSession(title: "Session")
        let messages = [makeTestChatMessage(role: .user, content: "Remember this.")]
        let memory = makeMemory(text: "Existing memory")
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
            ),
            systemPromptSettingsStore: InMemorySystemPromptSettingsStore()
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
            ),
            systemPromptSettingsStore: InMemorySystemPromptSettingsStore()
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
        var failures: [ChatContextOptionalInputFailure.Source] = []
        let builder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: retriever),
            toolCatalog: ToolCatalog(registry: ToolRegistry(tools: []), isEnabled: { true }),
            systemPromptSettingsStore: InMemorySystemPromptSettingsStore(),
            buildPolicy: ChatContextBuildPolicy { failure in
                failures.append(failure.source)
            }
        )

        let context = await builder.buildContext(
            session: nil,
            messages: [],
            systemPrompt: nil,
            includeTools: true
        )

        XCTAssertTrue(context.memories.isEmpty)
        XCTAssertEqual(failures, [.memories])
        XCTAssertEqual(retriever.capturedContexts.count, 1)
    }

    func testBuildContextIncludesSystemPromptForMemoryRetrievalAndResult() async {
        let prompt = makePrompt(
            title: "Translator",
            content: "Always answer in Chinese."
        )
        let retriever = RecordingMemoryRetriever(result: [])
        let builder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: retriever),
            toolCatalog: ToolCatalog(registry: ToolRegistry(tools: []), isEnabled: { true }),
            systemPromptSettingsStore: InMemorySystemPromptSettingsStore()
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

    func testBuildContextIncludesCurrentDateWhenEnabled() async {
        let currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        let retriever = RecordingMemoryRetriever(result: [])
        let builder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: retriever),
            toolCatalog: ToolCatalog(registry: ToolRegistry(tools: []), isEnabled: { true }),
            systemPromptSettingsStore: InMemorySystemPromptSettingsStore(
                settings: SystemPromptInjectionSettings(isCurrentDateEnabled: true)
            ),
            clock: FixedClock(now: currentDate)
        )

        let context = await builder.buildContext(
            session: nil,
            messages: [],
            systemPrompt: nil,
            includeTools: false
        )

        XCTAssertEqual(context.currentDate, currentDate)
        XCTAssertEqual(retriever.capturedContexts.first?.currentDate, currentDate)
    }
}

private enum TestMemoryError: Error {
    case failed
}

private struct FixedClock: AppClock {
    var now: Date
}

private func makePrompt(
    title: String,
    content: String,
    createdAt: Date = Date(timeIntervalSince1970: 1),
    updatedAt: Date = Date(timeIntervalSince1970: 1)
) -> SystemPromptRecord {
    SystemPromptRecord(
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}

private func makeMemory(
    scope: MemoryScope = .user,
    text: String,
    createdAt: Date = Date(timeIntervalSince1970: 1),
    updatedAt: Date? = nil
) -> MemoryRecord {
    MemoryRecord(
        scope: scope,
        text: text,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}

private final class InMemorySystemPromptSettingsStore: SystemPromptSettingsStore {
    private var settings: SystemPromptInjectionSettings

    init(settings: SystemPromptInjectionSettings = SystemPromptInjectionSettings()) {
        self.settings = settings
    }

    func loadInjectionSettings() -> SystemPromptInjectionSettings {
        settings
    }

    func saveInjectionSettings(_ settings: SystemPromptInjectionSettings) {
        self.settings = settings
    }
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
