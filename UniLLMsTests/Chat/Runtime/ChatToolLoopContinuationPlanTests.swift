//
//  ChatToolLoopContinuationPlanTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatToolLoopContinuationPlanTests: XCTestCase {
    func testPlanBuildsAssistantMessageForProviderToolLoopContinuation() {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let toolCalls = [
            makeToolCall(id: "call_1", toolID: "search"),
            makeToolCall(id: "call_2", toolID: "calendar")
        ]

        let plan = ChatToolLoopContinuationPlan(
            content: "I will use tools.",
            reasoning: "Need data.",
            toolCalls: toolCalls,
            createdAt: createdAt
        )

        XCTAssertEqual(plan.assistantMessage.role, .assistant)
        XCTAssertEqual(plan.assistantMessage.content, "I will use tools.")
        XCTAssertEqual(plan.assistantMessage.reasoning, "Need data.")
        XCTAssertEqual(plan.assistantMessage.toolCalls, toolCalls)
        XCTAssertEqual(plan.assistantMessage.createdAt, createdAt)
        XCTAssertEqual(plan.toolCalls, toolCalls)
    }

    func testPlanYieldsAssistantToolCallsTimelineEventBeforeStartedDisplayEvents() {
        let toolCalls = [
            makeToolCall(id: "call_1", toolID: "search"),
            makeToolCall(id: "call_2", toolID: "calendar")
        ]

        let plan = ChatToolLoopContinuationPlan(
            content: "",
            reasoning: "",
            toolCalls: toolCalls,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(plan.startedEvents.count, 3)
        XCTAssertEqual(plan.startedEvents.first, .timelineEvent(.assistantToolCalls(toolCalls)))
        XCTAssertEqual(plan.startedEvents.dropFirst().compactMap(Self.startedToolCallID), ["call_1", "call_2"])
    }

    func testPlanDoesNotYieldStartedEventsWhenThereAreNoToolCalls() {
        let plan = ChatToolLoopContinuationPlan(
            content: "Done.",
            reasoning: "",
            toolCalls: [],
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(plan.assistantMessage.toolCalls, [])
        XCTAssertEqual(plan.toolCalls, [])
        XCTAssertEqual(plan.startedEvents, [])
    }

    nonisolated private static func startedToolCallID(from event: ChatTurnEvent) -> String? {
        guard case let .displayDelta(delta) = event,
              delta.displayParts.count == 1,
              case let .toolEvent(.started(toolCall)) = delta.displayParts[0] else {
            return nil
        }

        return toolCall.id
    }

    private func makeToolCall(id: String, toolID: String) -> ChatToolCall {
        ChatToolCall(
            id: id,
            toolID: toolID,
            serializedArguments: #"{"query":"swift"}"#
        )
    }
}
