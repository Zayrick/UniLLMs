//
//  ChatResponsePresentationStateTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatResponsePresentationStateTests: XCTestCase {
    func testNewMessageRestoresDraftAfterFailureBeforeVisibleProgress() {
        let state = ChatResponsePresentationState.newMessage(
            prompt: "Hello",
            attachments: []
        )

        XCTAssertTrue(state.shouldRestoreDraftAfterFailure)
    }

    func testNewMessageKeepsResponseAfterVisibleContentProgress() {
        var state = ChatResponsePresentationState.newMessage(
            prompt: "Hello",
            attachments: []
        )

        state.recordVisibleProgress(from: ChatResponseDelta(content: "Hi"))

        XCTAssertFalse(state.shouldRestoreDraftAfterFailure)
    }

    func testNewMessageKeepsResponseAfterVisibleToolProgress() {
        var state = ChatResponsePresentationState.newMessage(
            prompt: "Use a tool",
            attachments: []
        )
        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "search",
            arguments: .object([:])
        )

        state.recordVisibleProgress(
            from: ChatResponseDelta(
                displayParts: [.toolEvent(.started(toolCall))]
            )
        )

        XCTAssertFalse(state.shouldRestoreDraftAfterFailure)
    }

    func testNewMessageIgnoresNonVisibleProviderProgress() {
        var state = ChatResponsePresentationState.newMessage(
            prompt: "Hidden",
            attachments: []
        )

        state.recordVisibleProgress(
            from: ChatResponseDelta(
                content: "hidden",
                displayParts: []
            )
        )

        XCTAssertTrue(state.shouldRestoreDraftAfterFailure)
    }

    func testReplacementMessageNeverRestoresDraftAfterFailure() {
        var state = ChatResponsePresentationState.replacementMessage(
            prompt: "Edited",
            attachments: []
        )

        XCTAssertFalse(state.shouldRestoreDraftAfterFailure)

        state.recordVisibleProgress(from: ChatResponseDelta(content: "Partial"))

        XCTAssertFalse(state.shouldRestoreDraftAfterFailure)
    }
}
