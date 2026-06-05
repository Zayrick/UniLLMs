//
//  ChatAssistantResponseMutationAdapterTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatAssistantResponseMutationAdapterTests: XCTestCase {
    func testApplyRunsMutationBeforeInvalidatingLayout() {
        let responseView = ResponseViewRecorder()
        let adapter = ChatAssistantResponseMutationAdapter<ResponseViewRecorder> {
            responseView.events.append(.layoutInvalidated)
        }

        adapter.apply(to: responseView) { responseView in
            responseView.events.append(.mutated("delta"))
        }

        XCTAssertEqual(
            responseView.events,
            [
                .mutated("delta"),
                .layoutInvalidated
            ]
        )
    }

    func testApplyInvalidatesLayoutAfterEachMutation() {
        let responseView = ResponseViewRecorder()
        let adapter = ChatAssistantResponseMutationAdapter<ResponseViewRecorder> {
            responseView.events.append(.layoutInvalidated)
        }

        adapter.apply(to: responseView) { responseView in
            responseView.events.append(.mutated("loading"))
        }
        adapter.apply(to: responseView) { responseView in
            responseView.events.append(.mutated("finished"))
        }

        XCTAssertEqual(
            responseView.events,
            [
                .mutated("loading"),
                .layoutInvalidated,
                .mutated("finished"),
                .layoutInvalidated
            ]
        )
    }
}

private final class ResponseViewRecorder {
    var events: [Event] = []
}

private enum Event: Equatable {
    case mutated(String)
    case layoutInvalidated
}
