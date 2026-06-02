//
//  LLMsProviderCoreTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class LLMsProviderCoreTests: XCTestCase {
    @MainActor
    func testProviderKindCodableRoundTripPreservesRawValue() throws {
        let kind: LLMsProviderKind = "customProvider"

        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(LLMsProviderKind.self, from: data)

        XCTAssertEqual(decoded.rawValue, "customProvider")
    }

    @MainActor
    func testProviderConfigurationSubscriptReturnsEmptyForMissingKey() {
        var configuration = LLMsProviderConfiguration()

        XCTAssertEqual(configuration["missing"], "")

        configuration["apiBase"] = "https://example.com/v1"

        XCTAssertEqual(configuration.values, ["apiBase": "https://example.com/v1"])
    }

    @MainActor
    func testProviderConfigurationDecodesLegacyFlatAndNestedStringValues() throws {
        let json = """
        {
            "apiKey": "legacy-key",
            "nested": {
                "apiBase": "https://legacy.example/v1"
            },
            "ignoredNumber": 123,
            "ignoredBool": true
        }
        """

        let configuration = try JSONDecoder().decode(
            LLMsProviderConfiguration.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(configuration.values, [
            "apiKey": "legacy-key",
            "apiBase": "https://legacy.example/v1"
        ])
    }

    @MainActor
    func testProviderRecordDisplayNameTrimsWhitespaceAndFallsBackToKind() {
        let named = LLMsProviderRecord(
            kind: LLMsProviderKind(rawValue: "openRouter"),
            name: "  Work Router  ",
            configuration: LLMsProviderConfiguration()
        )
        let unnamed = LLMsProviderRecord(
            kind: LLMsProviderKind(rawValue: "customKind"),
            name: "   ",
            configuration: LLMsProviderConfiguration()
        )

        XCTAssertEqual(named.displayName, "Work Router")
        XCTAssertEqual(unnamed.displayName, "customKind")
    }

    @MainActor
    func testConfigurationValueBindingReadsAndWritesProviderNameAndConfigValue() {
        var provider = LLMsProviderRecord(
            kind: .openRouter,
            name: "OpenRouter",
            configuration: LLMsProviderConfiguration()
        )

        provider.setConfigurationValue("Team Router", for: .providerName)
        provider.setConfigurationValue("sk-test", for: .configurationValue("apiKey"))

        XCTAssertEqual(provider.configurationValue(for: .providerName), "Team Router")
        XCTAssertEqual(provider.configurationValue(for: .configurationValue("apiKey")), "sk-test")
    }
}
