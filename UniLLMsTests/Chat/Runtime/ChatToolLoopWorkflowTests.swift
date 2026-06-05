//
//  ChatToolLoopWorkflowTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatToolLoopWorkflowTests: XCTestCase {
    func testDecisionFinishesWhenToolsAreUnavailable() async throws {
        let workflow = makeWorkflow(tool: WorkflowSuccessTool())
        let state = ChatToolLoopWorkflow.State(
            requestMessages: [makeTestChatMessage(role: .user, content: "Hello")]
        )
        let response = ChatAssistantResponseSnapshot(
            content: "Done.",
            reasoning: "",
            toolCalls: [makeToolCall()]
        )

        let decision = try await workflow.decision(
            after: response,
            state: state,
            context: ChatContext(availableTools: []),
            emit: { _ in XCTFail("Expected no tool events.") }
        )

        XCTAssertEqual(decision, .finish)
    }

    func testDecisionContinuesWithAssistantAndToolMessages() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tool = WorkflowSuccessTool()
        let workflow = makeWorkflow(tool: tool, clock: WorkflowFixedClock(now: now))
        let originalUserMessage = makeTestChatMessage(role: .user, content: "Use weather.")
        let state = ChatToolLoopWorkflow.State(requestMessages: [originalUserMessage])
        let toolCall = makeToolCall()
        let response = ChatAssistantResponseSnapshot(
            content: "I will check.",
            reasoning: "Need weather.",
            toolCalls: [toolCall]
        )
        var emittedEvents: [ChatTurnEvent] = []

        let decision = try await workflow.decision(
            after: response,
            state: state,
            context: ChatContext(availableTools: [tool.definition]),
            emit: { emittedEvents.append($0) }
        )

        guard case let .continue(nextState) = decision else {
            XCTFail("Expected tool loop to continue.")
            return
        }

        XCTAssertEqual(nextState.completedToolIterations, 1)
        XCTAssertEqual(nextState.requestMessages.map(\.role), [.user, .assistant, .tool])
        XCTAssertEqual(nextState.requestMessages[0], originalUserMessage)
        XCTAssertEqual(nextState.requestMessages[1].content, "I will check.")
        XCTAssertEqual(nextState.requestMessages[1].reasoning, "Need weather.")
        XCTAssertEqual(nextState.requestMessages[1].toolCalls, [toolCall])
        XCTAssertEqual(nextState.requestMessages[1].createdAt, now)
        XCTAssertEqual(nextState.requestMessages[2].toolCallID, "call_1")
        XCTAssertEqual(nextState.requestMessages[2].toolDisplayName, "Weather")
        XCTAssertEqual(nextState.requestMessages[2].toolStatus, .success)
        XCTAssertEqual(nextState.requestMessages[2].createdAt, now)
        XCTAssertEqual(emittedEvents.count, 4)
    }

    func testDecisionThrowsWhenMaximumIterationsIsReached() async {
        let workflow = makeWorkflow(
            tool: WorkflowSuccessTool(),
            maximumToolIterations: 0
        )
        let response = ChatAssistantResponseSnapshot(
            content: "",
            reasoning: "",
            toolCalls: [makeToolCall()]
        )

        do {
            _ = try await workflow.decision(
                after: response,
                state: ChatToolLoopWorkflow.State(requestMessages: []),
                context: ChatContext(availableTools: [WorkflowSuccessTool().definition]),
                emit: { _ in XCTFail("Expected no events after limit failure.") }
            )
            XCTFail("Expected tool iteration limit failure.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionLoopError, .exceededMaximumIterations(0))
        }
    }

    private func makeWorkflow(
        tool: any Tool,
        maximumToolIterations: Int = 8,
        clock: any AppClock = SystemAppClock()
    ) -> ChatToolLoopWorkflow {
        ChatToolLoopWorkflow(
            toolManager: ToolManager(
                catalog: ToolCatalog(
                    registry: ToolRegistry(tools: [tool]),
                    isEnabled: { true }
                )
            ),
            maximumToolIterations: maximumToolIterations,
            clock: clock
        )
    }

    private func makeToolCall() -> ChatToolCall {
        ChatToolCall(
            id: "call_1",
            toolID: WorkflowSuccessTool.toolID,
            serializedArguments: #"{"query":"weather"}"#
        )
    }
}

private struct WorkflowFixedClock: AppClock {
    var now: Date
}

private struct WorkflowSuccessTool: Tool {
    static let toolID = "weather"

    let definition = ToolDefinition(
        name: WorkflowSuccessTool.toolID,
        displayName: "Weather",
        summary: "Returns weather."
    )

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, content: "Sunny")
    }
}
