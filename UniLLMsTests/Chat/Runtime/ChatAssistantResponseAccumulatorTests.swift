//
//  ChatAssistantResponseAccumulatorTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatAssistantResponseAccumulatorTests: XCTestCase {
    func testAppendReturnsVisibleDeltaAndAccumulatesContentAndReasoning() {
        var accumulator = ChatAssistantResponseAccumulator()

        let visibleDelta = accumulator.append(
            delta: ChatResponseDelta(content: "Hello", reasoning: "Thinking"),
            context: ChatContext()
        )

        XCTAssertEqual(visibleDelta?.content, "Hello")
        XCTAssertEqual(visibleDelta?.reasoning, "Thinking")
        XCTAssertEqual(
            accumulator.snapshot,
            ChatAssistantResponseSnapshot(
                content: "Hello",
                reasoning: "Thinking",
                toolCalls: []
            )
        )
    }

    func testAppendRecordsToolCallsWithPresentationNameWithoutYieldingEmptyVisibleDelta() {
        var accumulator = ChatAssistantResponseAccumulator()
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "lookup",
            serializedArguments: #"{"query":"swift"}"#
        )
        let context = ChatContext(
            availableTools: [
                ToolDefinition(
                    name: "lookup",
                    displayName: "Knowledge Lookup",
                    summary: ""
                )
            ]
        )

        let visibleDelta = accumulator.append(
            delta: ChatResponseDelta(toolCalls: [toolCall]),
            context: context
        )

        XCTAssertNil(visibleDelta)
        XCTAssertEqual(accumulator.snapshot.toolCalls.first?.id, "call_1")
        XCTAssertEqual(accumulator.snapshot.toolCalls.first?.toolID, "lookup")
        XCTAssertEqual(accumulator.snapshot.toolCalls.first?.displayName, "Knowledge Lookup")
    }

    func testAppendReturnsDisplayPartsWithoutAccumulatingHiddenContent() {
        var accumulator = ChatAssistantResponseAccumulator()
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "lookup",
            serializedArguments: #"{"query":"swift"}"#
        )
        let delta = ChatResponseDelta(displayParts: [.toolEvent(.started(toolCall))])

        let visibleDelta = accumulator.append(delta: delta, context: ChatContext())

        XCTAssertEqual(visibleDelta?.displayParts, [.toolEvent(.started(toolCall))])
        XCTAssertEqual(accumulator.snapshot.content, "")
        XCTAssertEqual(accumulator.snapshot.reasoning, "")
        XCTAssertEqual(accumulator.snapshot.toolCalls, [])
    }
}
