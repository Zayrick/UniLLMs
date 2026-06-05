//
//  ChatActiveAssistantResponseLifecyclePlanTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatActiveAssistantResponseLifecyclePlanTests: XCTestCase {
    func testReceivedEmptyDeltaDoesNotPlanMutations() {
        let plan = ChatActiveAssistantResponseLifecyclePlan.received(delta: ChatResponseDelta())

        XCTAssertEqual(plan.actions, [])
    }

    func testReceivedVisibleDeltaRecordsReportsAndAppendsInOrder() {
        let delta = ChatResponseDelta(content: "Hello", reasoning: "Thinking")

        let plan = ChatActiveAssistantResponseLifecyclePlan.received(delta: delta)

        XCTAssertEqual(
            plan.actions,
            [
                .recordVisibleProgress(delta),
                .reportDelta(delta),
                .appendDisplayParts([
                    .reasoning("Thinking"),
                    .content("Hello")
                ])
            ]
        )
    }

    func testReceivedToolDeltaCountsAsVisibleProgress() {
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "search",
            serializedArguments: #"{"query":"swift"}"#
        )
        let delta = ChatResponseDelta(displayParts: [.toolEvent(.started(toolCall))])

        let plan = ChatActiveAssistantResponseLifecyclePlan.received(delta: delta)

        XCTAssertEqual(
            plan.actions,
            [
                .recordVisibleProgress(delta),
                .reportDelta(delta),
                .appendDisplayParts([.toolEvent(.started(toolCall))])
            ]
        )
    }

    func testReceivedHiddenProviderProgressReportsWithoutInvalidatingVisibleResponse() {
        let delta = ChatResponseDelta(
            content: "Hidden",
            displayParts: []
        )

        let plan = ChatActiveAssistantResponseLifecyclePlan.received(delta: delta)

        XCTAssertEqual(
            plan.actions,
            [
                .recordVisibleProgress(delta),
                .reportDelta(delta)
            ]
        )
    }

    func testPresentedFailureClearsActiveResponseOnlyWhenRecoveryRemovedIt() {
        XCTAssertEqual(
            ChatActiveAssistantResponseLifecyclePlan
                .presentedFailure(shouldClearActiveResponseView: true)
                .actions,
            [.clearActiveResponseView]
        )

        XCTAssertEqual(
            ChatActiveAssistantResponseLifecyclePlan
                .presentedFailure(shouldClearActiveResponseView: false)
                .actions,
            []
        )
    }

    func testCancelledOnlyPlaysFeedbackWhenStreamWasCancelled() {
        XCTAssertEqual(
            ChatActiveAssistantResponseLifecyclePlan
                .cancelled(didCancel: true)
                .actions,
            [.playCancellationFeedback]
        )

        XCTAssertEqual(
            ChatActiveAssistantResponseLifecyclePlan
                .cancelled(didCancel: false)
                .actions,
            []
        )
    }

    func testFinishedWithActiveResponseFinishesThenClearsAndDeactivates() {
        let plan = ChatActiveAssistantResponseLifecyclePlan.finished(hasActiveResponseView: true)

        XCTAssertEqual(
            plan.actions,
            [
                .finishActiveResponseView,
                .clearActiveResponseView,
                .clearActiveResponseContext,
                .deactivatePresentation
            ]
        )
    }

    func testFinishedAfterFailureRecoverySkipsMissingResponseViewButClearsContextAndDeactivates() {
        let plan = ChatActiveAssistantResponseLifecyclePlan.finished(hasActiveResponseView: false)

        XCTAssertEqual(
            plan.actions,
            [
                .clearActiveResponseView,
                .clearActiveResponseContext,
                .deactivatePresentation
            ]
        )
    }
}
