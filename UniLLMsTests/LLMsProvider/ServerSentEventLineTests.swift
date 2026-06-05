//
//  ServerSentEventLineTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ServerSentEventLineTests: XCTestCase {
    func testDataPayloadTrimsLineAndPayloadWhitespace() {
        XCTAssertEqual(
            ServerSentEventLine.dataPayload(from: "  data:  {\"ok\":true}  \n"),
            #"{"ok":true}"#
        )
    }

    func testDataPayloadIgnoresEmptyCommentAndNonDataLines() {
        XCTAssertNil(ServerSentEventLine.dataPayload(from: ""))
        XCTAssertNil(ServerSentEventLine.dataPayload(from: ": keep-alive"))
        XCTAssertNil(ServerSentEventLine.dataPayload(from: "event: message"))
    }

    func testDoneRecognizesTrimmedDonePayload() {
        XCTAssertTrue(ServerSentEventLine.isDone(" data: [DONE] \n"))
        XCTAssertFalse(ServerSentEventLine.isDone(": [DONE]"))
    }
}
