//
//  ChatMessageActionFailurePresentationTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatMessageActionFailurePresentationTests: XCTestCase {
    func testResponseInProgressFailureUsesResponseInProgressMessage() {
        let presentation = ChatMessageActionFailurePresentation.make(
            reason: .responseInProgress
        )

        XCTAssertEqual(presentation.message, .responseInProgress)
    }

    func testMessageUnavailableFailureUsesMessageUnavailableMessage() {
        let presentation = ChatMessageActionFailurePresentation.make(
            reason: .messageUnavailable
        )

        XCTAssertEqual(presentation.message, .messageUnavailable)
    }
}
