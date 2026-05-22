//
//  LLMsProviderRegistryTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class LLMsProviderRegistryTests: XCTestCase {
    func testAdaptersPreserveRegistrationOrder() {
        let first = RegistryTestProvider(kind: "first", displayName: "First")
        let second = RegistryTestProvider(kind: "second", displayName: "Second")

        let registry = LLMsProviderRegistry(adapters: [first, second])

        XCTAssertEqual(registry.adapters.map(\.kind.rawValue), ["first", "second"])
    }

    func testRegisteringSameKindReplacesAdapterWithoutDuplicatingOrder() {
        let first = RegistryTestProvider(kind: "provider", displayName: "Original")
        let replacement = RegistryTestProvider(kind: "provider", displayName: "Replacement")
        let registry = LLMsProviderRegistry(adapters: [first])

        registry.register(replacement)

        XCTAssertEqual(registry.adapters.map(\.displayName), ["Replacement"])
        XCTAssertEqual(registry.adapters.count, 1)
    }

    func testAdapterForUnknownKindReturnsNil() {
        let registry = LLMsProviderRegistry()

        XCTAssertNil(registry.adapter(for: LLMsProviderKind(rawValue: "missing")))
    }
}

private struct RegistryTestProvider: LLMsProviderAdapter {
    let kind: LLMsProviderKind
    let displayName: String

    var capabilities: Set<LLMsProviderCapability> {
        []
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration()
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .manual
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
