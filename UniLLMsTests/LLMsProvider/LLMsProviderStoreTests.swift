//
//  LLMsProviderStoreTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class LLMsProviderStoreTests: LLMsProviderStoreTestCase {
    func testAddingOpenRouterProvidersAssignsUUIDsAndUniqueNames() throws {
        let first = try makeOpenRouterProviderDraft()
        store.saveProvider(first)
        let second = try makeOpenRouterProviderDraft()
        store.saveProvider(second)
        let third = try makeOpenRouterProviderDraft()
        store.saveProvider(third)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(second.id, third.id)
        XCTAssertEqual(first.name, "OpenRouter")
        XCTAssertEqual(second.name, "OpenRouter 1")
        XCTAssertEqual(third.name, "OpenRouter 2")
        XCTAssertEqual(first.configuration[OpenRouterProvider.ConfigurationKey.apiBase], openRouterDefaultAPIBase)
    }

    func testOpenRouterDraftDoesNotPersistUntilSaved() throws {
        let draft = try makeOpenRouterProviderDraft()

        XCTAssertTrue(store.fetchProviders().isEmpty)

        store.saveProvider(draft)

        let reloaded = try XCTUnwrap(store.fetchProviders().first)
        XCTAssertEqual(reloaded.id, draft.id)
        XCTAssertEqual(reloaded.name, "OpenRouter")
    }

    func testProviderConfigurationUpdatesPersistByUUID() throws {
        var provider = try addOpenRouterProvider()
        provider.name = "Work Router"
        provider.configuration[OpenRouterProvider.ConfigurationKey.apiKey] = "sk-or-test"
        provider.configuration[OpenRouterProvider.ConfigurationKey.apiBase] = "https://example.com/v1"
        provider.models = [
            LLMProviderModel(id: "openai/gpt-4", name: "GPT-4", contextLength: 8192)
        ]
        store.updateProvider(provider)

        let reloaded = try XCTUnwrap(store.fetchProviders().first)
        XCTAssertEqual(reloaded.id, provider.id)
        XCTAssertEqual(reloaded.name, "Work Router")
        XCTAssertEqual(reloaded.configuration[OpenRouterProvider.ConfigurationKey.apiKey], "sk-or-test")
        XCTAssertEqual(reloaded.configuration[OpenRouterProvider.ConfigurationKey.apiBase], "https://example.com/v1")
        XCTAssertEqual(reloaded.models, provider.models)
    }

    func testProviderRecordDecodesLegacyConfigurationFields() throws {
        let json = """
        [{
            "id": "00000000-0000-0000-0000-000000000001",
            "kind": "openRouter",
            "name": "Legacy Router",
            "apiKey": "legacy-key",
            "apiBase": "https://legacy.example/v1",
            "models": [],
            "createdAt": "2026-05-11T00:00:00Z"
        }]
        """
        defaults.set(try XCTUnwrap(json.data(using: .utf8)), forKey: "providers")

        let provider = try XCTUnwrap(store.fetchProviders().first)

        XCTAssertEqual(provider.configuration[OpenRouterProvider.ConfigurationKey.apiKey], "legacy-key")
        XCTAssertEqual(provider.configuration[OpenRouterProvider.ConfigurationKey.apiBase], "https://legacy.example/v1")
    }

    func testModelUpdatesDoNotOverwriteUnsavedConfiguration() throws {
        let provider = try addOpenRouterProvider()
        let models = [
            LLMProviderModel(id: "openai/gpt-4", name: "GPT-4", contextLength: 8192)
        ]
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        store.updateProviderModels(
            id: provider.id,
            models: models,
            modelsUpdatedAt: updatedAt
        )

        let reloaded = try XCTUnwrap(store.fetchProviders().first)
        XCTAssertEqual(reloaded.name, "OpenRouter")
        XCTAssertEqual(reloaded.configuration[OpenRouterProvider.ConfigurationKey.apiKey], "")
        XCTAssertEqual(reloaded.configuration[OpenRouterProvider.ConfigurationKey.apiBase], openRouterDefaultAPIBase)
        XCTAssertEqual(reloaded.models, models)
        XCTAssertEqual(reloaded.modelsUpdatedAt, updatedAt)
    }

    func testModelUpdatesForDraftDoNotPersist() throws {
        let draft = try makeOpenRouterProviderDraft()

        store.updateProviderModels(
            id: draft.id,
            models: [
                LLMProviderModel(id: "openai/gpt-4", name: "GPT-4", contextLength: 8192)
            ],
            modelsUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(store.fetchProviders().isEmpty)
    }

    func testDeletingProviderRemovesMatchingUUIDOnly() throws {
        let first = try addOpenRouterProvider()
        let second = try addOpenRouterProvider()

        store.deleteProvider(id: first.id)

        let providers = store.fetchProviders()
        XCTAssertEqual(providers.map(\.id), [second.id])
    }

    func testMovingProviderPersistsProviderOrder() throws {
        let first = try addOpenRouterProvider()
        let second = try addOpenRouterProvider()
        let third = try addOpenRouterProvider()

        store.moveProvider(from: 0, to: 2)

        XCTAssertEqual(store.fetchProviders().map(\.id), [second.id, third.id, first.id])

        store.moveProvider(from: 2, to: 0)

        XCTAssertEqual(store.fetchProviders().map(\.id), [first.id, second.id, third.id])
    }

    func testFetchingProviderByIDReturnsMatchingProvider() throws {
        _ = try addOpenRouterProvider()
        let second = try addOpenRouterProvider()

        let fetched = try XCTUnwrap(store.fetchProvider(id: second.id))
        let missingID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

        XCTAssertEqual(fetched.id, second.id)
        XCTAssertEqual(fetched.name, second.name)
        XCTAssertNil(store.fetchProvider(id: missingID))
    }

    func testSelectedModelSelectionPersistsByProviderUUIDAndModelID() throws {
        var provider = try addOpenRouterProvider()
        provider.name = "Work Router"
        provider.models = [
            LLMProviderModel(id: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4", contextLength: 200_000)
        ]
        store.updateProvider(provider)

        store.saveSelectedModelSelection(
            LLMModelSelection(
                providerID: provider.id,
                providerName: "Stale Name",
                modelID: "anthropic/claude-sonnet-4",
                modelName: "Stale Model Name"
            )
        )

        let selection = try XCTUnwrap(store.fetchSelectedModelSelection())
        XCTAssertEqual(selection.providerID, provider.id)
        XCTAssertEqual(selection.providerName, "Work Router")
        XCTAssertEqual(selection.modelID, "anthropic/claude-sonnet-4")
        XCTAssertEqual(selection.modelName, "Claude Sonnet 4")
    }

    func testDeletingSelectedProviderClearsSelectedModelSelection() throws {
        var provider = try addOpenRouterProvider()
        provider.models = [
            LLMProviderModel(id: "openai/gpt-4.1", name: "GPT-4.1", contextLength: 1_000_000)
        ]
        store.updateProvider(provider)
        store.saveSelectedModelSelection(
            LLMModelSelection(
                providerID: provider.id,
                providerName: provider.name,
                modelID: "openai/gpt-4.1",
                modelName: "GPT-4.1"
            )
        )

        store.deleteProvider(id: provider.id)

        XCTAssertNil(store.fetchSelectedModelSelection())
    }

    func testRemovingSelectedModelClearsSelectedModelSelection() throws {
        var provider = try addOpenRouterProvider()
        provider.models = [
            LLMProviderModel(id: "openai/gpt-4.1", name: "GPT-4.1", contextLength: 1_000_000)
        ]
        store.updateProvider(provider)
        store.saveSelectedModelSelection(
            LLMModelSelection(
                providerID: provider.id,
                providerName: provider.name,
                modelID: "openai/gpt-4.1",
                modelName: "GPT-4.1"
            )
        )

        store.updateProviderModels(
            id: provider.id,
            models: [
                LLMProviderModel(id: "openai/gpt-4.1-mini", name: "GPT-4.1 mini", contextLength: 1_000_000)
            ],
            modelsUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertNil(store.fetchSelectedModelSelection())
    }

    func testRefreshingSelectedModelUpdatesRecoveredDisplayName() throws {
        var provider = try addOpenRouterProvider()
        provider.models = [
            LLMProviderModel(id: "openai/gpt-4.1", name: "GPT-4.1", contextLength: 1_000_000)
        ]
        store.updateProvider(provider)
        store.saveSelectedModelSelection(
            LLMModelSelection(
                providerID: provider.id,
                providerName: provider.name,
                modelID: "openai/gpt-4.1",
                modelName: "GPT-4.1"
            )
        )

        store.updateProviderModels(
            id: provider.id,
            models: [
                LLMProviderModel(id: "openai/gpt-4.1", name: "GPT-4.1 Latest", contextLength: 1_000_000)
            ],
            modelsUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let selection = try XCTUnwrap(store.fetchSelectedModelSelection())
        XCTAssertEqual(selection.modelName, "GPT-4.1 Latest")
    }

    func testChatModelSelectionDisplayNameFallsBackToIDWhenModelNameIsMissing() {
        let selection = LLMModelSelection(
            providerID: UUID(),
            providerName: "OpenAI Compatible",
            modelID: "gpt-4.1-mini",
            modelName: nil
        )

        XCTAssertEqual(selection.displayName, "gpt-4.1-mini")
    }

    func testSavingSelectedModelSelectionPostsStoreScopedNotification() throws {
        let observer = SelectedModelSelectionObserver(store: store)
        defer {
            observer.invalidate()
        }
        let provider = try addOpenRouterProvider()

        store.saveSelectedModelSelection(
            LLMModelSelection(
                providerID: provider.id,
                providerName: provider.name,
                modelID: "openai/gpt-4.1",
                modelName: "GPT-4.1"
            )
        )

        XCTAssertEqual(observer.notificationCount, 1)
    }

    func testClearingMissingSelectedModelSelectionDoesNotPostNotification() {
        let observer = SelectedModelSelectionObserver(store: store)
        defer {
            observer.invalidate()
        }

        store.clearSelectedModelSelection()

        XCTAssertEqual(observer.notificationCount, 0)
    }

    func testUpdatingUnrelatedProviderDoesNotPostSelectedModelNotification() throws {
        var selectedProvider = try addOpenRouterProvider()
        selectedProvider.models = [
            LLMProviderModel(id: "openai/gpt-4.1", name: "GPT-4.1")
        ]
        store.updateProvider(selectedProvider)
        let unrelatedProvider = try addOpenRouterProvider()
        store.saveSelectedModelSelection(
            LLMModelSelection(
                providerID: selectedProvider.id,
                providerName: selectedProvider.name,
                modelID: "openai/gpt-4.1",
                modelName: "GPT-4.1"
            )
        )
        let observer = SelectedModelSelectionObserver(store: store)
        defer {
            observer.invalidate()
        }

        store.updateProvider(unrelatedProvider)

        XCTAssertEqual(observer.notificationCount, 0)
    }
}

private final class SelectedModelSelectionObserver {
    private var token: NSObjectProtocol?
    private let observedStore: LLMProviderStore
    private(set) var notificationCount = 0

    init(store: LLMProviderStore) {
        observedStore = store
        token = NotificationCenter.default.addObserver(
            forName: LLMProviderStore.selectedModelSelectionDidChangeNotification,
            object: store,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  notification.object as AnyObject === observedStore else {
                return
            }

            notificationCount += 1
        }
    }

    func invalidate() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }

    deinit {
        invalidate()
    }
}
