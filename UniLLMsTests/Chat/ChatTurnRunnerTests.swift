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
