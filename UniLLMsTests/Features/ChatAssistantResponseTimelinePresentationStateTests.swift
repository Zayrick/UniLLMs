//
//  ChatAssistantResponseTimelinePresentationStateTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatAssistantResponseTimelinePresentationStateTests: XCTestCase {
    private typealias State = ChatAssistantResponseTimelinePresentationState

    func testReasoningThenContentCreatesSeparateSegmentsAndFinishesThinking() {
        var state = State()

        let reasoningActions = state.appendDisplayParts([.reasoning("Need data.")])

        XCTAssertEqual(
            reasoningActions,
            [
                .createThinkingSegment(segment(0)),
                .appendReasoning(segmentID: segment(0), text: "Need data.")
            ]
        )

        let contentActions = state.appendDisplayParts([.content("Answer")])

        XCTAssertEqual(
            contentActions,
            [
                .finishThinkingSegment(segment(0), animated: true),
                .createContentSegment(segment(1)),
                .appendContentMarkdown(segmentID: segment(1), markdown: "Answer")
            ]
        )
        XCTAssertFalse(state.isEmpty)
        XCTAssertEqual(state.rawContentMarkdown, "Answer")
        XCTAssertFalse(state.shouldShowCopyMarkdownButton)
    }

    func testConsecutiveContentAppendsToTheSameContentSegment() {
        var state = State()

        let actions = state.appendDisplayParts([
            .content("Hel"),
            .content("lo")
        ])

        XCTAssertEqual(
            actions,
            [
                .createContentSegment(segment(0)),
                .appendContentMarkdown(segmentID: segment(0), markdown: "Hel"),
                .appendContentMarkdown(segmentID: segment(0), markdown: "lo")
            ]
        )
        XCTAssertEqual(state.rawContentMarkdown, "Hello")
        XCTAssertFalse(state.isEmpty)
    }

    func testToolCompletionUsesTheSectionRecordedWhenTheToolStartedBeforeContent() {
        var state = State()
        let toolCall = makeToolCall()

        _ = state.appendDisplayParts([.toolEvent(.started(toolCall))])
        _ = state.appendDisplayParts([.content("Visible answer")])

        let actions = state.appendDisplayParts([
            .toolEvent(.completed(toolCall, result: "Sunny"))
        ])

        XCTAssertEqual(
            actions,
            [
                .appendToolInvocation(
                    segmentID: segment(0),
                    invocation: State.ToolInvocationPresentation(
                        callID: "call_1",
                        displayName: "Weather",
                        state: .completed,
                        detail: "Sunny"
                    )
                )
            ]
        )
    }

    func testToolFailureUsesTheSectionRecordedWhenTheToolStartedBeforeContent() {
        var state = State()
        let toolCall = makeToolCall()

        _ = state.appendDisplayParts([.toolEvent(.started(toolCall))])
        _ = state.appendDisplayParts([.content("Visible answer")])

        let actions = state.appendDisplayParts([
            .toolEvent(.failed(toolCall, message: "Timeout"))
        ])

        XCTAssertEqual(
            actions,
            [
                .appendToolInvocation(
                    segmentID: segment(0),
                    invocation: State.ToolInvocationPresentation(
                        callID: "call_1",
                        displayName: "Weather",
                        state: .failed(message: "Timeout"),
                        detail: "Timeout"
                    )
                )
            ]
        )
    }

    func testUnknownToolCompletionCreatesANewActiveThinkingSection() {
        var state = State()
        _ = state.appendDisplayParts([.content("Visible answer")])

        let actions = state.appendDisplayParts([
            .toolEvent(.completed(makeToolCall(), result: "Sunny"))
        ])

        XCTAssertEqual(
            actions,
            [
                .createThinkingSegment(segment(1)),
                .appendToolInvocation(
                    segmentID: segment(1),
                    invocation: State.ToolInvocationPresentation(
                        callID: "call_1",
                        displayName: "Weather",
                        state: .completed,
                        detail: "Sunny"
                    )
                )
            ]
        )
        XCTAssertFalse(state.isEmpty)
    }

    func testStoredContentFinishesActiveThinkingWithoutAnimationAndCreatesFinishedContentSegment() {
        var state = State()
        _ = state.appendDisplayParts([.reasoning("Restored thought")])

        let actions = state.appendStoredContentMarkdown("Stored answer")

        XCTAssertEqual(
            actions,
            [
                .finishThinkingSegment(segment(0), animated: false),
                .createContentSegment(segment(1)),
                .setFinishedContentMarkdown(segmentID: segment(1), markdown: "Stored answer")
            ]
        )
        XCTAssertEqual(state.rawContentMarkdown, "Stored answer")
        XCTAssertFalse(state.shouldShowCopyMarkdownButton)
    }

    func testErrorMarksResponseFinishedAndAllowsCopyingPartialMarkdown() {
        var state = State()
        _ = state.appendDisplayParts([.content("Partial")])

        let actions = state.setError()

        XCTAssertEqual(actions, [.finishContentSegment(segment(0))])
        XCTAssertTrue(state.isResponseFinished)
        XCTAssertTrue(state.shouldShowCopyMarkdownButton)
    }

    func testReasoningOnlyErrorFinishesThinkingWithoutShowingCopy() {
        var state = State()
        _ = state.appendDisplayParts([.reasoning("Thinking")])

        let actions = state.setError()

        XCTAssertEqual(actions, [.finishThinkingSegment(segment(0), animated: true)])
        XCTAssertTrue(state.isResponseFinished)
        XCTAssertFalse(state.shouldShowCopyMarkdownButton)
    }

    func testFinishStreamingContentFinishesContentAndThinkingSegments() {
        var state = State()
        _ = state.appendDisplayParts([
            .reasoning("Think"),
            .content("Answer")
        ])

        let actions = state.finishStreamingContent()

        XCTAssertEqual(
            actions,
            [
                .finishContentSegment(segment(1)),
                .finishThinkingSegment(segment(0), animated: true)
            ]
        )
        XCTAssertTrue(state.shouldShowCopyMarkdownButton)
    }

    func testRepeatedFinishDoesNotReplayTimelineActions() {
        var state = State()
        _ = state.appendDisplayParts([.content("Answer")])

        let firstActions = state.finishStreamingContent()
        let secondActions = state.finishStreamingContent()

        XCTAssertEqual(firstActions, [.finishContentSegment(segment(0))])
        XCTAssertEqual(secondActions, [])
        XCTAssertTrue(state.isResponseFinished)
        XCTAssertTrue(state.shouldShowCopyMarkdownButton)
    }

    func testErrorAfterFinishDoesNotReplayTimelineActions() {
        var state = State()
        _ = state.appendDisplayParts([
            .reasoning("Think"),
            .content("Answer")
        ])
        _ = state.finishStreamingContent()

        let actions = state.setError()

        XCTAssertEqual(actions, [])
        XCTAssertTrue(state.isResponseFinished)
        XCTAssertTrue(state.shouldShowCopyMarkdownButton)
    }

    private func segment(_ rawValue: Int) -> State.SegmentID {
        State.SegmentID(rawValue)
    }

    private func makeToolCall() -> ChatToolCall {
        ChatToolCall(
            id: "call_1",
            toolID: "weather",
            serializedArguments: #"{"city":"Paris"}"#,
            displayName: "Weather"
        )
    }
}
