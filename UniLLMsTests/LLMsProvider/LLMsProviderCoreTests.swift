//
//  LLMsProviderCoreTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class LLMsProviderCoreTests: XCTestCase {
    func testProviderKindCodableRoundTripPreservesRawValue() throws {
        let kind: LLMsProviderKind = "customProvider"

        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(LLMsProviderKind.self, from: data)

        XCTAssertEqual(decoded.rawValue, "customProvider")
    }

    func testProviderConfigurationSubscriptReturnsEmptyForMissingKey() {
        var configuration = LLMsProviderConfiguration()

        XCTAssertEqual(configuration["missing"], "")

        configuration["apiBase"] = "https://example.com/v1"

        XCTAssertEqual(configuration.values, ["apiBase": "https://example.com/v1"])
    }

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

    func testProviderRecordDisplayNameTrimsWhitespaceAndFallsBackToKind() {
        let named = LLMsProviderRecord(
            kind: LLMsProviderKind(rawValue: "openRouter"),
            name: "  Work Router  ",
            configuration: LLMsProviderConfiguration(),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let unnamed = LLMsProviderRecord(
            kind: LLMsProviderKind(rawValue: "customKind"),
            name: "   ",
            configuration: LLMsProviderConfiguration(),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(named.displayName, "Work Router")
        XCTAssertEqual(unnamed.displayName, "customKind")
    }

    func testProviderRecordDecodesLegacyMissingCreatedAtAsDistantPast() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "kind": "openRouter",
            "name": "Legacy Router",
            "configuration": {
                "values": {
                    "apiBase": "https://openrouter.ai/api/v1"
                }
            }
        }
        """

        let provider = try JSONDecoder().decode(
            LLMsProviderRecord.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(provider.id, id)
        XCTAssertEqual(provider.createdAt, .distantPast)
    }

    func testConfigurationValueBindingReadsAndWritesProviderNameAndConfigValue() {
        var provider = LLMsProviderRecord(
            kind: .openRouter,
            name: "OpenRouter",
            configuration: LLMsProviderConfiguration(),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        provider.setConfigurationValue("Team Router", for: .providerName)
        provider.setConfigurationValue("sk-test", for: .configurationValue("apiKey"))

        XCTAssertEqual(provider.configurationValue(for: .providerName), "Team Router")
        XCTAssertEqual(provider.configurationValue(for: .configurationValue("apiKey")), "sk-test")
    }
}
