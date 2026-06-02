//
//  SecretValueTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class SecretValueTests: XCTestCase {
    @MainActor
    func testDescriptionMasksNonEmptySecret() {
        let secret = SecretValue(rawValue: "sk-test")

        XCTAssertEqual(secret.description, String(repeating: "\u{2022}", count: 8))
    }

    @MainActor
    func testDescriptionReturnsEmptyStringForEmptySecret() {
        let secret = SecretValue(rawValue: "")

        XCTAssertEqual(secret.description, "")
    }

    @MainActor
    func testCodableRoundTripPreservesRawValue() throws {
        let secret = SecretValue(rawValue: "private-value")

        let data = try JSONEncoder().encode(secret)
        let decoded = try JSONDecoder().decode(SecretValue.self, from: data)

        XCTAssertEqual(decoded, secret)
    }
}
