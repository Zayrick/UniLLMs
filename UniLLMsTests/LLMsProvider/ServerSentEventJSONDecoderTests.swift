//
//  ServerSentEventJSONDecoderTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ServerSentEventJSONDecoderTests: XCTestCase {
    func testDecodeIgnoresNonDataLines() throws {
        let decoded = try ServerSentEventJSONDecoder.decode(
            Payload.self,
            from: ": keep-alive",
            invalidPayloadError: { DecodeFailure.invalid }
        )

        XCTAssertNil(decoded)
    }

    func testDecodeSkipsDoneSignalByDefault() throws {
        let decoded = try ServerSentEventJSONDecoder.decode(
            Payload.self,
            from: "data: [DONE]",
            invalidPayloadError: { DecodeFailure.invalid }
        )

        XCTAssertNil(decoded)
    }

    func testDecodeReadsJSONDataPayload() throws {
        let decoded = try ServerSentEventJSONDecoder.decode(
            Payload.self,
            from: #"data: {"value":"ok"}"#,
            invalidPayloadError: { DecodeFailure.invalid }
        )

        XCTAssertEqual(decoded, Payload(value: "ok"))
    }

    func testDecodeThrowsInvalidPayloadErrorForMalformedJSON() {
        XCTAssertThrowsError(
            try ServerSentEventJSONDecoder.decode(
                Payload.self,
                from: "data: {",
                invalidPayloadError: { DecodeFailure.invalid }
            )
        ) { error in
            XCTAssertEqual(error as? DecodeFailure, .invalid)
        }
    }

    func testDecodeCanTreatDoneSignalAsInvalidPayload() {
        XCTAssertThrowsError(
            try ServerSentEventJSONDecoder.decode(
                Payload.self,
                from: "data: [DONE]",
                skipsDoneSignal: false,
                invalidPayloadError: { DecodeFailure.invalid }
            )
        ) { error in
            XCTAssertEqual(error as? DecodeFailure, .invalid)
        }
    }
}

private struct Payload: Decodable, Equatable {
    var value: String
}

private enum DecodeFailure: Error {
    case invalid
}
