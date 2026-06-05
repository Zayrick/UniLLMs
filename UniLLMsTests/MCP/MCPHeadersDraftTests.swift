//
//  MCPHeadersDraftTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class MCPHeadersDraftTests: XCTestCase {
    func testEmptyTextResolvesToEmptyHeaders() {
        let draft = MCPHeadersDraft(text: " \n ")

        XCTAssertEqual(draft.headersForSaving(), [:])
        XCTAssertEqual(draft.headersResult(), .valid([:]))
    }

    func testValidJSONStringDictionaryResolvesToHeaders() {
        let draft = MCPHeadersDraft(text: #"{"Authorization":"Bearer test","X-Team":"Core"}"#)

        XCTAssertEqual(
            draft.headersForSaving(),
            [
                "Authorization": "Bearer test",
                "X-Team": "Core"
            ]
        )
    }

    func testNonStringHeaderValueIsInvalid() {
        let draft = MCPHeadersDraft(text: #"{"Retry":3}"#)

        XCTAssertEqual(draft.headersResult(), .invalid(.invalidJSON))
        XCTAssertNil(draft.headersForSaving())
    }

    func testInvalidJSONIsInvalid() {
        let draft = MCPHeadersDraft(text: "{")

        XCTAssertEqual(draft.headersResult(), .invalid(.invalidJSON))
        XCTAssertEqual(
            MCPHeadersDraftError.invalidJSON.localizedDescription,
            "Headers must be a JSON object with string keys and string values."
        )
    }

    func testHeadersInitializerFormatsHeadersAsSortedCompactJSON() {
        let draft = MCPHeadersDraft(headers: ["X-Team": "Core", "Authorization": "Bearer test"])

        XCTAssertEqual(draft.text, #"{"Authorization":"Bearer test","X-Team":"Core"}"#)
    }

    func testHeadersInitializerFallsBackToEmptyTextWhenEncodingFails() {
        let draft = MCPHeadersDraft(
            headers: ["Authorization": "Bearer test"],
            coder: FailingMCPHeadersJSONCoder()
        )

        XCTAssertEqual(draft.text, "")
    }
}

private struct FailingMCPHeadersJSONCoder: MCPHeadersJSONCoding {
    func decodeHeaders(from text: String) throws -> [String: String] {
        [:]
    }

    func encodeHeaders(_ headers: [String: String]) throws -> String {
        throw FailingMCPHeadersJSONCoderError.failed
    }
}

private enum FailingMCPHeadersJSONCoderError: Error {
    case failed
}
