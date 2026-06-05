//
//  LLMsProviderAPIBaseURLTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class LLMsProviderAPIBaseURLTests: XCTestCase {
    func testEffectiveStringUsesTrimmedCustomAPIBaseWhenPresent() {
        XCTAssertEqual(
            LLMsProviderAPIBaseURL.effectiveString(
                apiBase: " https://example.com/v1/ ",
                defaultAPIBase: "https://default.example/v1"
            ),
            "https://example.com/v1/"
        )
    }

    func testEffectiveStringFallsBackToDefaultWhenBlank() {
        XCTAssertEqual(
            LLMsProviderAPIBaseURL.effectiveString(
                apiBase: " \n ",
                defaultAPIBase: "https://default.example/v1"
            ),
            "https://default.example/v1"
        )
    }

    func testNormalizedURLTrimsPathSlashes() throws {
        let url = try XCTUnwrap(
            LLMsProviderAPIBaseURL.normalizedURL(baseString: "https://example.com///v1///")
        )

        XCTAssertEqual(url.absoluteString, "https://example.com/v1")
    }

    func testNormalizedURLAcceptsHTTPAndHTTPSOnly() {
        XCTAssertNotNil(LLMsProviderAPIBaseURL.normalizedURL(baseString: "https://example.com/v1"))
        XCTAssertNotNil(LLMsProviderAPIBaseURL.normalizedURL(baseString: "http://localhost:11434/v1"))
        XCTAssertNil(LLMsProviderAPIBaseURL.normalizedURL(baseString: "file:///tmp/models"))
    }

    func testNormalizedURLRejectsMissingHostQueryAndFragment() {
        XCTAssertNil(LLMsProviderAPIBaseURL.normalizedURL(baseString: "https:///v1"))
        XCTAssertNil(LLMsProviderAPIBaseURL.normalizedURL(baseString: "https://example.com/v1?token=1"))
        XCTAssertNil(LLMsProviderAPIBaseURL.normalizedURL(baseString: "https://example.com/v1#models"))
    }
}
