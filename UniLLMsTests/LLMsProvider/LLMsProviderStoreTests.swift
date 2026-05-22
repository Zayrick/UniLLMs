//
//  LLMsProviderStoreTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class LLMsProviderStoreTests: LLMsProviderStoreTestCase {
    func testAddingProvidersAssignsUUIDsAndUniqueNames() throws {
        let first = try makeTestProviderDraft()
        store.saveProvider(first)
        let second = try makeTestProviderDraft()
        store.saveProvider(second)
        let third = try makeTestProviderDraft()
        store.saveProvider(third)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(second.id, third.id)
        XCTAssertEqual(first.name, "Test Remote")
        XCTAssertEqual(second.name, "Test Remote 1")
        XCTAssertEqual(third.name, "Test Remote 2")
        XCTAssertEqual(first.configuration[TestRemoteProvider.ConfigurationKey.apiBase], testProviderDefaultAPIBase)
    }

    func testProviderDraftDoesNotPersistUntilSaved() throws {
        let draft = try makeTestProviderDraft()

        XCTAssertTrue(store.fetchProviders().isEmpty)

        store.saveProvider(draft)

        let reloaded = try XCTUnwrap(store.fetchProviders().first)
        XCTAssertEqual(reloaded.id, draft.id)
        XCTAssertEqual(reloaded.name, "Test Remote")
    }

    func testProviderConfigurationUpdatesPersistByUUID() throws {
        var provider = try addTestProvider()
        provider.name = "Work Provider"
        provider.configuration[TestRemoteProvider.ConfigurationKey.apiKey] = "sk-test"
        provider.configuration[TestRemoteProvider.ConfigurationKey.apiBase] = "https://example.com/v1"
        provider.models = [
            LLMProviderModel(id: "openai/gpt-4", name: "GPT-4", contextLength: 8192)
        ]
        store.updateProvider(provider)

        let reloaded = try XCTUnwrap(store.fetchProviders().first)
        XCTAssertEqual(reloaded.id, provider.id)
        XCTAssertEqual(reloaded.name, "Work Provider")
        XCTAssertEqual(reloaded.configuration[TestRemoteProvider.ConfigurationKey.apiKey], "sk-test")
        XCTAssertEqual(reloaded.configuration[TestRemoteProvider.ConfigurationKey.apiBase], "https://example.com/v1")
        XCTAssertEqual(reloaded.models, provider.models)
    }

    func testProviderRecordDecodesLegacyConfigurationFields() throws {
        let json = """
        [{
            "id": "00000000-0000-0000-0000-000000000001",
            "kind": "testRemoteProvider",
            "name": "Legacy Provider",
            "apiKey": "legacy-key",
            "apiBase": "https://legacy.example/v1",
            "models": [],
            "createdAt": "2026-05-11T00:00:00Z"
        }]
        """
        defaults.set(try XCTUnwrap(json.data(using: .utf8)), forKey: "providers")

        let provider = try XCTUnwrap(store.fetchProviders().first)

        XCTAssertEqual(provider.configuration[TestRemoteProvider.ConfigurationKey.apiKey], "legacy-key")
        XCTAssertEqual(provider.configuration[TestRemoteProvider.ConfigurationKey.apiBase], "https://legacy.example/v1")
    }

    func testModelUpdatesDoNotOverwriteUnsavedConfiguration() throws {
        let provider = try addTestProvider()
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
        XCTAssertEqual(reloaded.name, "Test Remote")
        XCTAssertEqual(reloaded.configuration[TestRemoteProvider.ConfigurationKey.apiKey], "")
        XCTAssertEqual(reloaded.configuration[TestRemoteProvider.ConfigurationKey.apiBase], testProviderDefaultAPIBase)
        XCTAssertEqual(reloaded.models, models)
        XCTAssertEqual(reloaded.modelsUpdatedAt, updatedAt)
    }

    func testModelUpdatesForDraftDoNotPersist() throws {
        let draft = try makeTestProviderDraft()

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
        let first = try addTestProvider()
        let second = try addTestProvider()

        store.deleteProvider(id: first.id)

        let providers = store.fetchProviders()
        XCTAssertEqual(providers.map(\.id), [second.id])
    }

    func testMovingProviderPersistsProviderOrder() throws {
        let first = try addTestProvider()
        let second = try addTestProvider()
        let third = try addTestProvider()

        store.moveProvider(from: 0, to: 2)

        XCTAssertEqual(store.fetchProviders().map(\.id), [second.id, third.id, first.id])

        store.moveProvider(from: 2, to: 0)

        XCTAssertEqual(store.fetchProviders().map(\.id), [first.id, second.id, third.id])
    }

    func testFetchingProviderByIDReturnsMatchingProvider() throws {
        _ = try addTestProvider()
        let second = try addTestProvider()

        let fetched = try XCTUnwrap(store.fetchProvider(id: second.id))
        let missingID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

        XCTAssertEqual(fetched.id, second.id)
        XCTAssertEqual(fetched.name, second.name)
        XCTAssertNil(store.fetchProvider(id: missingID))
    }

    func testSelectedModelSelectionPersistsByProviderUUIDAndModelID() throws {
        var provider = try addTestProvider()
        provider.name = "Work Provider"
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
        XCTAssertEqual(selection.providerName, "Work Provider")
        XCTAssertEqual(selection.modelID, "anthropic/claude-sonnet-4")
        XCTAssertEqual(selection.modelName, "Claude Sonnet 4")
    }

    func testDeletingSelectedProviderClearsSelectedModelSelection() throws {
        var provider = try addTestProvider()
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
        var provider = try addTestProvider()
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
        var provider = try addTestProvider()
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
        let provider = try addTestProvider()

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
        var selectedProvider = try addTestProvider()
        selectedProvider.models = [
            LLMProviderModel(id: "openai/gpt-4.1", name: "GPT-4.1")
        ]
        store.updateProvider(selectedProvider)
        let unrelatedProvider = try addTestProvider()
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
