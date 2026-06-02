//
//  LLMsProviderStoreTestCase.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

class LLMsProviderStoreTestCase: UserDefaultsBackedTestCase {
    @MainActor
    var store: LLMProviderStore {
        LLMProviderStore(defaults: defaults, storageKey: "providers")
    }

    @MainActor
    func makeProviderManager(
        adapters: [any LLMsProviderAdapter] = [TestRemoteProvider()]
    ) -> LLMsProviderManager {
        LLMsProviderManager(
            registry: LLMsProviderRegistry(adapters: adapters),
            store: store
        )
    }

    @MainActor
    func makeTestProviderDraft() throws -> LLMsProviderRecord {
        try makeProviderManager().makeProviderDraft(kind: TestRemoteProvider.providerKind)
    }

    @discardableResult
    @MainActor
    func addTestProvider() throws -> LLMsProviderRecord {
        let provider = try makeTestProviderDraft()
        store.saveProvider(provider)
        return provider
    }

    @MainActor
    var testProviderDefaultAPIBase: String {
        TestRemoteProvider().defaultConfiguration[TestRemoteProvider.ConfigurationKey.apiBase]
    }
}

struct TestRemoteProvider: LLMsProviderAdapter {
    static let providerKind = LLMsProviderKind(rawValue: "testRemoteProvider")

    enum ConfigurationKey {
        static let apiKey = "apiKey"
        static let apiBase = "apiBase"
    }

    var kind: LLMsProviderKind {
        Self.providerKind
    }

    var displayName: String {
        "Test Remote"
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.modelList, .streamingChat]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration(
            values: [
                ConfigurationKey.apiKey: "",
                ConfigurationKey.apiBase: "https://test.example/v1"
            ]
        )
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .remote
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
