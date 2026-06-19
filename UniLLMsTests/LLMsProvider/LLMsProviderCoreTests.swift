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

    func testReasoningEffortResolutionMapsUnsupportedDisabledToOmitWithoutChangingStoredValue() {
        let options = LLMsProviderReasoningEffortOptions(
            levels: [
                LLMsProviderReasoningEffort(value: 1, providerValue: "low", title: "Low"),
                LLMsProviderReasoningEffort(value: 2, providerValue: "high", title: "High")
            ]
        )

        let resolution = options.resolution(forStoredValue: 0)

        XCTAssertEqual(resolution.storedValue, 0)
        XCTAssertEqual(resolution.resolvedValue, -1)
        XCTAssertNil(resolution.providerValue)
        XCTAssertEqual(resolution.activePositiveLevelCount, 0)
    }

    func testReasoningEffortResolutionClampsPositiveValueToHighestSupportedLevel() {
        let options = LLMsProviderReasoningEffortOptions(
            levels: [
                LLMsProviderReasoningEffort(value: 0, providerValue: "none", title: "Off"),
                LLMsProviderReasoningEffort(value: 1, providerValue: "minimal", title: "Minimal"),
                LLMsProviderReasoningEffort(value: 2, providerValue: "low", title: "Low"),
                LLMsProviderReasoningEffort(value: 3, providerValue: "high", title: "High")
            ]
        )

        let resolution = options.resolution(forStoredValue: 8)

        XCTAssertEqual(resolution.storedValue, 8)
        XCTAssertEqual(resolution.resolvedValue, 3)
        XCTAssertEqual(resolution.providerValue, "high")
        XCTAssertEqual(resolution.positiveLevelCount, 3)
        XCTAssertEqual(resolution.activePositiveLevelCount, 3)
    }

    func testReasoningEffortOptionsIgnoreInvalidAndDuplicateLevels() {
        let options = LLMsProviderReasoningEffortOptions(
            levels: [
                LLMsProviderReasoningEffort(value: 2, providerValue: "high", title: "High"),
                LLMsProviderReasoningEffort(value: 2, providerValue: "duplicate", title: "Duplicate"),
                LLMsProviderReasoningEffort(value: -1, providerValue: "omit", title: "Omit"),
                LLMsProviderReasoningEffort(value: 1, providerValue: " ", title: "Blank"),
                LLMsProviderReasoningEffort(value: 0, providerValue: "none", title: "Off")
            ]
        )

        XCTAssertEqual(options.levels.map(\.value), [0, 2])
    }

    func testProviderModelNormalizesReasoningEffortsCaseInsensitively() {
        let model = LLMsProviderModel(
            id: "model",
            reasoningEfforts: [" High ", "high", "LOW", "low"]
        )

        XCTAssertEqual(model.reasoningEfforts, ["High", "LOW"])
    }

    func testProviderConfigurationNormalizerPreservesReasoningMetadata() {
        let provider = LLMsProviderRecord(
            kind: .openRouter,
            name: "OpenRouter",
            configuration: LLMsProviderConfiguration(),
            models: [
                LLMsProviderModel(
                    id: " openai/gpt-5.2 ",
                    name: "  GPT-5.2  ",
                    contextLength: 400_000,
                    reasoningEfforts: ["high", "minimal"],
                    isReasoningMandatory: true
                ),
                LLMsProviderModel(id: "   ")
            ]
        )

        let normalized = LLMsProviderConfigurationNormalizer.normalizedProvider(provider)

        XCTAssertEqual(normalized.models.count, 1)
        XCTAssertEqual(normalized.models[0].id, "openai/gpt-5.2")
        XCTAssertEqual(normalized.models[0].name, "GPT-5.2")
        XCTAssertEqual(normalized.models[0].contextLength, 400_000)
        XCTAssertEqual(normalized.models[0].reasoningEfforts, ["high", "minimal"])
        XCTAssertTrue(normalized.models[0].isReasoningMandatory)
    }
}
