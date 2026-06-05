//
//  ChatToolCallExecutionResultPlanTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatToolCallExecutionResultPlanTests: XCTestCase {
    func testSuccessfulResultBuildsCompletedEventsAndProviderMessage() {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let displayToolCall = makeDisplayToolCall()

        let plan = ChatToolCallExecutionResultPlan(
            displayToolCall: displayToolCall,
            providerToolCallID: "provider_call_1",
            toolDisplayName: "Search",
            result: ToolResult(callID: "call_1", content: "Sunny"),
            createdAt: createdAt
        )

        guard case let .completed(completedCall, result) = plan.event else {
            XCTFail("Expected completed event.")
            return
        }
        XCTAssertEqual(completedCall.displayName, "Search")
        XCTAssertEqual(result, "Sunny")
        XCTAssertEqual(plan.turnEvents, Self.events(for: plan.event))
        XCTAssertEqual(plan.providerMessage.role, .tool)
        XCTAssertEqual(plan.providerMessage.content, "Sunny")
        XCTAssertEqual(plan.providerMessage.toolCallID, "provider_call_1")
        XCTAssertEqual(plan.providerMessage.toolDisplayName, "Search")
        XCTAssertEqual(plan.providerMessage.toolStatus, .success)
        XCTAssertEqual(plan.providerMessage.createdAt, createdAt)
    }

    func testErrorStatusResultBuildsFailedEventsAndErrorProviderMessage() {
        let plan = ChatToolCallExecutionResultPlan(
            displayToolCall: makeDisplayToolCall(),
            providerToolCallID: "provider_call_1",
            toolDisplayName: "Search",
            result: ToolResult(
                callID: "call_1",
                content: "Invalid query.",
                status: .error
            ),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        guard case let .failed(failedCall, message) = plan.event else {
            XCTFail("Expected failed event.")
            return
        }
        XCTAssertEqual(failedCall.displayName, "Search")
        XCTAssertEqual(message, "Invalid query.")
        XCTAssertEqual(plan.turnEvents, Self.events(for: plan.event))
        XCTAssertEqual(plan.providerMessage.content, plan.event.providerMessageContent)
        XCTAssertEqual(plan.providerMessage.toolStatus, .error)
    }

    func testThrownFailureBuildsFailedEventsAndErrorProviderMessage() {
        let plan = ChatToolCallExecutionResultPlan(
            displayToolCall: makeDisplayToolCall(),
            providerToolCallID: "provider_call_1",
            toolDisplayName: "Search",
            failureMessage: "Network failed.",
            createdAt: Date(timeIntervalSince1970: 1)
        )

        guard case let .failed(_, message) = plan.event else {
            XCTFail("Expected failed event.")
            return
        }
        XCTAssertEqual(message, "Network failed.")
        XCTAssertEqual(plan.turnEvents, Self.events(for: plan.event))
        XCTAssertEqual(plan.providerMessage.toolCallID, "provider_call_1")
        XCTAssertEqual(plan.providerMessage.toolDisplayName, "Search")
        XCTAssertEqual(plan.providerMessage.toolStatus, .error)
    }

    private static func events(for event: ChatToolEvent) -> [ChatTurnEvent] {
        [
            .timelineEvent(.toolEvent(event)),
            .displayDelta(ChatResponseDelta(displayParts: [.toolEvent(event)]))
        ]
    }

    private func makeDisplayToolCall() -> ChatToolCall {
        ChatToolCall(
            id: "call_1",
            toolID: "search",
            arguments: .object(["query": .string("weather")]),
            displayName: "Search"
        )
    }
}
