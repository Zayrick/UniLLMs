//
//  LLMsProviderStoreTestCase.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

class LLMsProviderStoreTestCase: UserDefaultsBackedTestCase {
    var store: LLMProviderStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = LLMProviderStore(defaults: defaults, storageKey: "providers")
    }

    override func tearDownWithError() throws {
        store = nil
        try super.tearDownWithError()
    }

    func makeProviderManager(
        adapters: [any LLMsProviderAdapter] = LLMsProviderCatalog.makeRegistry().adapters
    ) -> LLMsProviderManager {
        LLMsProviderManager(
            registry: LLMsProviderRegistry(adapters: adapters),
            store: store
        )
    }

    func makeOpenRouterProviderDraft() throws -> LLMsProviderRecord {
        try makeProviderManager().makeProviderDraft(kind: .openRouter)
    }

    @discardableResult
    func addOpenRouterProvider() throws -> LLMsProviderRecord {
        let provider = try makeOpenRouterProviderDraft()
        store.saveProvider(provider)
        return provider
    }

    var openRouterDefaultAPIBase: String {
        OpenRouterProvider().defaultConfiguration[OpenRouterProvider.ConfigurationKey.apiBase]
    }
}
