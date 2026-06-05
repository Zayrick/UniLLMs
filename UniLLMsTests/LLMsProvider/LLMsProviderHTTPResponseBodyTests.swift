//
//  LLMsProviderHTTPResponseBodyTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class LLMsProviderHTTPResponseBodyTests: XCTestCase {
    private let url = URL(string: "https://example.com")!

    func testPreviewJoinsLinesWithNewlines() async throws {
        let body = try await LLMsProviderHTTPResponseBody.preview(
            from: Self.lines(["first", "second", "third"])
        )

        XCTAssertEqual(body, "first\nsecond\nthird")
    }

    func testPreviewStopsAfterCharacterLimitIsExceeded() async throws {
        let body = try await LLMsProviderHTTPResponseBody.preview(
            from: Self.lines(["1234", "5678", "90"]),
            characterLimit: 5
        )

        XCTAssertEqual(body, "1234\n5678")
    }

    func testValidateDataResponseAcceptsHTTPSuccess() throws {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertNoThrow(
            try LLMsProviderHTTPResponseValidator.validateDataResponse(
                response: response,
                data: Data(),
                serviceName: "Provider",
                invalidResponseError: ValidatorError.invalidResponse,
                serverStatusError: ValidatorError.serverStatus
            )
        )
    }

    func testValidateDataResponseRejectsNonHTTPResponse() throws {
        let response = URLResponse(
            url: url,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        XCTAssertThrowsError(
            try LLMsProviderHTTPResponseValidator.validateDataResponse(
                response: response,
                data: Data(),
                serviceName: "Provider",
                invalidResponseError: ValidatorError.invalidResponse,
                serverStatusError: ValidatorError.serverStatus
            )
        ) { error in
            XCTAssertEqual(error as? ValidatorError, .invalidResponse("Provider"))
        }
    }

    func testValidateDataResponseIncludesHTTPStatusBody() throws {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertThrowsError(
            try LLMsProviderHTTPResponseValidator.validateDataResponse(
                response: response,
                data: Data("slow down".utf8),
                serviceName: "Provider",
                invalidResponseError: ValidatorError.invalidResponse,
                serverStatusError: ValidatorError.serverStatus
            )
        ) { error in
            XCTAssertEqual(error as? ValidatorError, .serverStatus("Provider", 429, "slow down"))
        }
    }

    private static func lines(_ values: [String]) -> AsyncStream<String> {
        AsyncStream(String.self, bufferingPolicy: .unbounded) { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
    }
}

private enum ValidatorError: Error, Equatable {
    case invalidResponse(String)
    case serverStatus(String, Int, String?)
}
