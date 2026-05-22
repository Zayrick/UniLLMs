//
//  ChatTurnRunnerTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ChatTurnRunnerTests: LLMsProviderStoreTestCase {
    func testChatTurnRunnerMapsErrorToolResultToFailedToolEvent() async throws {
        let providerManager = makeProviderManager(adapters: [ToolLoopTestProvider()])
        let runner = ChatTurnRunner(
            responseStreamer: ChatResponseStreamer(providerManager: providerManager),
            toolManager: ToolManager(
                catalog: ToolCatalog(
                    registry: ToolRegistry(tools: [ErrorStatusTool()]),
                    isEnabled: { true }
                )
            )
        )
        let provider = LLMsProviderRecord(
            kind: ToolLoopTestProvider.providerKind,
            name: "Tool Loop Test",
            configuration: LLMsProviderConfiguration()
        )
        let tool = ErrorStatusTool()
        let context = ChatContext(
            session: ChatSession(title: "Tool Error"),
            messages: [
                ChatMessage(role: .user, content: "Use the failing tool.")
            ],
            availableTools: [tool.definition]
        )

        var toolEvents: [ChatToolEvent] = []
        var content = ""
        for try await event in runner.streamResponse(
            provider: provider,
            modelID: "test-model",
            context: context
        ) {
            switch event {
            case let .displayDelta(delta):
                content += delta.content
                for part in delta.displayParts {
                    if case let .toolEvent(toolEvent) = part {
                        toolEvents.append(toolEvent)
                    }
                }
            case .timelineEvent:
                continue
            }
        }

        XCTAssertEqual(content, "Recovered after tool error.")
        XCTAssertEqual(toolEvents.count, 2)
        guard let firstEvent = toolEvents.first,
              case let .started(startedCall) = firstEvent else {
            XCTFail("Expected a started tool event.")
            return
        }
        guard let lastEvent = toolEvents.last,
              case let .failed(failedCall, message) = lastEvent else {
            XCTFail("Expected a failed tool event.")
            return
        }
        XCTAssertEqual(startedCall.id, "call_1")
        XCTAssertEqual(failedCall.id, "call_1")
        XCTAssertEqual(failedCall.presentationName, "Failing Tool")
        XCTAssertEqual(message, "Invalid tool input.")
    }

    func testChatTurnRunnerKeepsSystemPromptSingleAcrossToolLoop() async throws {
        let adapter = CapturingToolLoopProvider()
        let providerManager = makeProviderManager(adapters: [adapter])
        let runner = ChatTurnRunner(
            responseStreamer: ChatResponseStreamer(providerManager: providerManager),
            toolManager: ToolManager(
                catalog: ToolCatalog(
                    registry: ToolRegistry(tools: [ErrorStatusTool()]),
                    isEnabled: { true }
                )
            )
        )
        let provider = LLMsProviderRecord(
            kind: CapturingToolLoopProvider.providerKind,
            name: "Tool Loop Capture",
            configuration: LLMsProviderConfiguration()
        )
        let prompt = SystemPromptRecord(
            title: "Translator",
            content: "Always answer in Chinese."
        )
        let tool = ErrorStatusTool()
        let context = ChatContext(
            messages: [
                ChatMessage(role: .user, content: "Use the failing tool.")
            ],
            systemPrompt: prompt,
            availableTools: [tool.definition]
        )

        for try await _ in runner.streamResponse(
            provider: provider,
            modelID: "test-model",
            context: context
        ) {}

        XCTAssertEqual(adapter.requests.count, 2)
        guard adapter.requests.count == 2 else {
            return
        }

        XCTAssertEqual(adapter.requests[0].messages.map(\.role), [.user])
        XCTAssertEqual(adapter.requests[1].messages.map(\.role), [.user, .assistant, .tool])
        XCTAssertTrue(adapter.requests.allSatisfy { request in
            request.context.systemPrompt == prompt
                && !request.messages.contains(where: { $0.role == .system })
        })
    }

    func testChatTurnRunnerUsesOriginalToolCallIDForProviderToolMessage() async throws {
        let adapter = CapturingToolLoopProvider()
        let providerManager = makeProviderManager(adapters: [adapter])
        let runner = ChatTurnRunner(
            responseStreamer: ChatResponseStreamer(providerManager: providerManager),
            toolManager: ToolManager(
                catalog: ToolCatalog(
                    registry: ToolRegistry(tools: [MismatchedCallIDTool()]),
                    isEnabled: { true }
                )
            )
        )
        let provider = LLMsProviderRecord(
            kind: CapturingToolLoopProvider.providerKind,
            name: "Tool Loop Capture",
            configuration: LLMsProviderConfiguration()
        )
        let tool = MismatchedCallIDTool()
        let context = ChatContext(
            messages: [
                ChatMessage(role: .user, content: "Use the tool.")
            ],
            availableTools: [tool.definition]
        )

        for try await _ in runner.streamResponse(
            provider: provider,
            modelID: "test-model",
            context: context
        ) {}

        XCTAssertEqual(adapter.requests.count, 2)
        XCTAssertEqual(adapter.requests.last?.messages.last?.toolCallID, "call_1")
    }
}

private struct ToolLoopTestProvider: LLMsProviderAdapter {
    static let providerKind = LLMsProviderKind(rawValue: "toolLoopTest")

    var kind: LLMsProviderKind {
        Self.providerKind
    }

    var displayName: String {
        "Tool Loop Test Provider"
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.streamingChat, .tools]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration()
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .manual
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            if request.messages.contains(where: { $0.role == .tool }) {
                continuation.yield(ChatResponseDelta(content: "Recovered after tool error."))
            } else {
                continuation.yield(
                    ChatResponseDelta(
                        toolCalls: [
                            ChatToolCall(
                                id: "call_1",
                                toolID: ErrorStatusTool.toolID,
                                arguments: "{}"
                            )
                        ]
                    )
                )
            }
            continuation.finish()
        }
    }
}

private final class CapturingToolLoopProvider: LLMsProviderAdapter {
    static let providerKind = LLMsProviderKind(rawValue: "capturingToolLoopTest")

    private(set) var requests: [ChatRequest] = []

    var kind: LLMsProviderKind {
        Self.providerKind
    }

    var displayName: String {
        "Capturing Tool Loop Test Provider"
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.streamingChat, .tools]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration()
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .manual
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            if request.messages.contains(where: { $0.role == .tool }) {
                continuation.yield(ChatResponseDelta(content: "Done."))
            } else {
                continuation.yield(
                    ChatResponseDelta(
                        toolCalls: [
                            ChatToolCall(
                                id: "call_1",
                                toolID: ErrorStatusTool.toolID,
                                arguments: "{}"
                            )
                        ]
                    )
                )
            }
            continuation.finish()
        }
    }
}

private struct ErrorStatusTool: Tool {
    static let toolID = "failing_tool"

    let definition = ToolDefinition(
        name: ErrorStatusTool.toolID,
        displayName: "Failing Tool",
        summary: "Reports an execution error without throwing."
    )

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(
            callID: call.id,
            content: "Invalid tool input.",
            status: .error
        )
    }
}

private struct MismatchedCallIDTool: Tool {
    let definition = ToolDefinition(
        name: ErrorStatusTool.toolID,
        displayName: "Mismatched Tool",
        summary: "Returns a mismatched call ID."
    )

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(
            callID: "wrong_call_id",
            content: "OK"
        )
    }
}
