//
//  ChatToolCallExecutorTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatToolCallExecutorTests: XCTestCase {
    func testExecuteEmitsCompletedToolEventAndReturnsProviderToolMessage() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tool = SuccessTool()
        let executor = makeExecutor(tool: tool, clock: FixedClock(now: now))
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: SuccessTool.toolID,
            arguments: .object(["query": .string("weather")])
        )
        var events: [ChatTurnEvent] = []

        let messages = await executor.execute(
            [toolCall],
            context: ChatContext(
                session: makeTestChatSession(title: "Tools"),
                availableTools: [tool.definition]
            ),
            emit: { events.append($0) }
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.role, .tool)
        XCTAssertEqual(messages.first?.content, "Sunny")
        XCTAssertEqual(messages.first?.toolCallID, "call_1")
        XCTAssertEqual(messages.first?.toolDisplayName, "Weather")
        XCTAssertEqual(messages.first?.toolStatus, .success)
        XCTAssertEqual(messages.first?.createdAt, now)

        guard let firstEvent = events.first,
              case let .timelineEvent(.toolEvent(.completed(completedCall, result))) = firstEvent else {
            XCTFail("Expected completed timeline event.")
            return
        }
        XCTAssertEqual(completedCall.presentationName, "Weather")
        XCTAssertEqual(result, "Sunny")
    }

    func testExecutePreservesExistingDisplayName() async {
        let tool = SuccessTool()
        let executor = makeExecutor(tool: tool)
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: SuccessTool.toolID,
            arguments: .object([:]),
            displayName: "Stored Name"
        )

        let messages = await executor.execute(
            [toolCall],
            context: ChatContext(availableTools: [tool.definition]),
            emit: { _ in }
        )

        XCTAssertEqual(messages.first?.toolDisplayName, "Stored Name")
    }

    func testExecuteMapsInvalidArgumentsToFailedToolEvent() async {
        let tool = SuccessTool()
        let executor = makeExecutor(tool: tool)
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: SuccessTool.toolID,
            arguments: .string("not an object")
        )
        var events: [ChatTurnEvent] = []

        let messages = await executor.execute(
            [toolCall],
            context: ChatContext(availableTools: [tool.definition]),
            emit: { events.append($0) }
        )

        XCTAssertEqual(messages.first?.toolStatus, .error)
        guard let firstEvent = events.first,
              case let .timelineEvent(.toolEvent(.failed(failedCall, message))) = firstEvent else {
            XCTFail("Expected failed timeline event.")
            return
        }
        XCTAssertEqual(failedCall.presentationName, "Weather")
        XCTAssertFalse(message.isEmpty)
    }

    private func makeExecutor(
        tool: any Tool,
        clock: any AppClock = SystemAppClock()
    ) -> ChatToolCallExecutor {
        ChatToolCallExecutor(
            toolManager: ToolManager(
                catalog: ToolCatalog(
                    registry: ToolRegistry(tools: [tool]),
                    isEnabled: { true }
                )
            ),
            clock: clock
        )
    }
}

private struct FixedClock: AppClock {
    var now: Date
}

private struct SuccessTool: Tool {
    static let toolID = "weather"

    let definition = ToolDefinition(
        name: SuccessTool.toolID,
        displayName: "Weather",
        summary: "Returns weather."
    )

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, content: "Sunny")
    }
}
