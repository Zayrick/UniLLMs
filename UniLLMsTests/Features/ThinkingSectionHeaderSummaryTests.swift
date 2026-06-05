//
//  ThinkingSectionHeaderSummaryTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ThinkingSectionHeaderSummaryTests: XCTestCase {
    func testEmptySummaryHasNoFinishedTitle() {
        let summary = ThinkingSectionHeaderSummary()

        XCTAssertTrue(summary.isEmpty)
        XCTAssertNil(summary.finishedTitle)
    }

    func testFinishedTitleIncludesReasoningAndUniqueToolCalls() {
        var summary = ThinkingSectionHeaderSummary()

        summary.recordReasoningStep()
        summary.recordReasoningStep()
        summary.recordToolInvocation(callID: "call_1")
        summary.recordToolInvocation(callID: "call_1")
        summary.recordToolInvocation(callID: "call_2")

        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.reasoningStepCount, 2)
        XCTAssertEqual(summary.toolCallIDs, Set(["call_1", "call_2"]))
        XCTAssertEqual(summary.finishedTitle, "2 reasoning steps, 2 tool calls")
    }

    func testFinishedTitleUsesSingularLabels() {
        var summary = ThinkingSectionHeaderSummary()

        summary.recordReasoningStep()
        summary.recordToolInvocation(callID: "call_1")

        XCTAssertEqual(summary.finishedTitle, "1 reasoning step, 1 tool call")
    }
}
