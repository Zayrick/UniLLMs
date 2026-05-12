//
//  UniLLMsTests.swift
//  UniLLMsTests
//
//  Covers provider storage, provider manager behavior, and OpenRouter stream parsing non-UI behavior.
//  Created by Zayrick on 2026/5/11.
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class UniLLMsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: LLMProviderStore!
    private var markdownRendererTraits: UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(displayScale: 2.0),
            UITraitCollection(preferredContentSizeCategory: .large)
        ])
    }

    override func setUpWithError() throws {
        suiteName = "UniLLMsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = LLMProviderStore(defaults: defaults, storageKey: "providers")
    }

    override func tearDownWithError() throws {
        if let defaults = defaults, let suiteName = suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        store = nil
    }

    func testAddingOpenRouterProvidersAssignsUUIDsAndUniqueNames() throws {
        let first = store.makeOpenRouterProviderDraft()
        store.saveProvider(first)
        let second = store.makeOpenRouterProviderDraft()
        store.saveProvider(second)
        let third = store.makeOpenRouterProviderDraft()
        store.saveProvider(third)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(second.id, third.id)
        XCTAssertEqual(first.name, "OpenRouter")
        XCTAssertEqual(second.name, "OpenRouter 1")
        XCTAssertEqual(third.name, "OpenRouter 2")
        XCTAssertEqual(first.apiBase, LLMProviderRecord.openRouterDefaultAPIBase)
    }

    func testOpenRouterDraftDoesNotPersistUntilSaved() throws {
        let draft = store.makeOpenRouterProviderDraft()

        XCTAssertTrue(store.fetchProviders().isEmpty)

        store.saveProvider(draft)

        let reloaded = try XCTUnwrap(store.fetchProviders().first)
        XCTAssertEqual(reloaded.id, draft.id)
        XCTAssertEqual(reloaded.name, "OpenRouter")
    }

    func testProviderConfigurationUpdatesPersistByUUID() throws {
        var provider = store.addOpenRouterProvider()
        provider.name = "Work Router"
        provider.apiKey = "sk-or-test"
        provider.apiBase = "https://example.com/v1"
        provider.models = [
            LLMProviderModel(id: "openai/gpt-4", name: "GPT-4", contextLength: 8192)
        ]
        store.updateProvider(provider)

        let reloaded = try XCTUnwrap(store.fetchProviders().first)
        XCTAssertEqual(reloaded.id, provider.id)
        XCTAssertEqual(reloaded.name, "Work Router")
        XCTAssertEqual(reloaded.apiKey, "sk-or-test")
        XCTAssertEqual(reloaded.apiBase, "https://example.com/v1")
        XCTAssertEqual(reloaded.configuration.apiKey, "sk-or-test")
        XCTAssertEqual(reloaded.configuration.apiBase, "https://example.com/v1")
        XCTAssertEqual(reloaded.models, provider.models)
    }

    func testProviderManagerCreatesOpenRouterDraftFromRegisteredAdapter() throws {
        let registry = LLMsProviderRegistry(adapters: [OpenRouterProvider()])
        let manager = LLMsProviderManager(registry: registry, store: store)

        let draft = try manager.makeProviderDraft(kind: .openRouter)

        XCTAssertEqual(draft.kind, .openRouter)
        XCTAssertEqual(draft.name, "OpenRouter")
        XCTAssertEqual(draft.configuration.apiBase, LLMsProviderRecord.openRouterDefaultAPIBase)
        XCTAssertTrue(draft.models.isEmpty)
    }

    func testProviderManagerRejectsUnregisteredProviderKind() throws {
        let manager = LLMsProviderManager(registry: LLMsProviderRegistry(), store: store)

        XCTAssertThrowsError(
            try manager.makeProviderDraft(kind: LLMsProviderKind(rawValue: "missing"))
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Unsupported LLM provider: missing")
        }
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

        XCTAssertEqual(provider.configuration.apiKey, "legacy-key")
        XCTAssertEqual(provider.configuration.apiBase, "https://legacy.example/v1")
    }

    func testModelUpdatesDoNotOverwriteUnsavedConfiguration() throws {
        let provider = store.addOpenRouterProvider()
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
        XCTAssertEqual(reloaded.apiKey, "")
        XCTAssertEqual(reloaded.apiBase, LLMProviderRecord.openRouterDefaultAPIBase)
        XCTAssertEqual(reloaded.models, models)
        XCTAssertEqual(reloaded.modelsUpdatedAt, updatedAt)
    }

    func testModelUpdatesForDraftDoNotPersist() throws {
        let draft = store.makeOpenRouterProviderDraft()

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
        let first = store.addOpenRouterProvider()
        let second = store.addOpenRouterProvider()

        store.deleteProvider(id: first.id)

        let providers = store.fetchProviders()
        XCTAssertEqual(providers.map(\.id), [second.id])
    }

    func testFetchingProviderByIDReturnsMatchingProvider() throws {
        _ = store.addOpenRouterProvider()
        let second = store.addOpenRouterProvider()

        let fetched = try XCTUnwrap(store.fetchProvider(id: second.id))
        let missingID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

        XCTAssertEqual(fetched.id, second.id)
        XCTAssertEqual(fetched.name, second.name)
        XCTAssertNil(store.fetchProvider(id: missingID))
    }

    func testSelectedModelSelectionPersistsByProviderUUIDAndModelID() throws {
        var provider = store.addOpenRouterProvider()
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
        var provider = store.addOpenRouterProvider()
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
        var provider = store.addOpenRouterProvider()
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
        var provider = store.addOpenRouterProvider()
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

    func testMarkdownThematicBreakRendersAsVisualDivider() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let attributedText = renderer.render(markdown: "Above\n\n---\n\nBelow")

        XCTAssertFalse(attributedText.string.contains("---"))
        XCTAssertTrue(attributedText.string.contains("Above"))
        XCTAssertTrue(attributedText.string.contains("Below"))
        XCTAssertTrue(attributedText.containsTextAttachment)
    }

    func testMarkdownNestedListRendersIncreasingIndents() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let attributedText = renderer.render(markdown: "- Parent\n  - Child\n    - Grandchild")

        let parentStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Parent"))
        let childStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Child"))
        let grandchildStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Grandchild"))

        XCTAssertGreaterThan(childStyle.firstLineHeadIndent, parentStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(grandchildStyle.firstLineHeadIndent, childStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(childStyle.headIndent, parentStyle.headIndent)
        XCTAssertGreaterThan(grandchildStyle.headIndent, childStyle.headIndent)
    }

    func testMarkdownOrderedListUsesStableContentIndentAcrossDigitWidths() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let attributedText = renderer.render(markdown: "9. Nine\n10. Ten")

        let nineStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Nine"))
        let tenStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Ten"))

        XCTAssertEqual(nineStyle.headIndent, tenStyle.headIndent)
    }

    func testOpenRouterStreamParserDecodesContentDelta() throws {
        let delta = try XCTUnwrap(
            OpenRouterAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
            )
        )

        XCTAssertEqual(delta.content, "Hello")
        XCTAssertEqual(delta.reasoning, "")
    }

    func testOpenRouterStreamParserDecodesReasoningDelta() throws {
        let delta = try XCTUnwrap(
            OpenRouterAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"choices":[{"delta":{"reasoning":"Thinking"}}]}"#
            )
        )

        XCTAssertEqual(delta.content, "")
        XCTAssertEqual(delta.reasoning, "Thinking")
    }

    func testOpenRouterStreamParserDecodesReasoningDetailsDelta() throws {
        let delta = try XCTUnwrap(
            OpenRouterAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.text","text":"Step "},{"type":"reasoning.summary","summary":"summary"}]}}]}"#
            )
        )

        XCTAssertEqual(delta.content, "")
        XCTAssertEqual(delta.reasoning, "Step summary")
    }

    func testOpenRouterStreamParserIgnoresCommentsAndDoneEvents() throws {
        XCTAssertNil(try OpenRouterAPIClient.streamDelta(fromServerSentEventLine: ": OPENROUTER PROCESSING"))
        XCTAssertNil(try OpenRouterAPIClient.streamDelta(fromServerSentEventLine: "data: [DONE]"))
    }

    func testOpenRouterStreamParserThrowsMidStreamError() throws {
        XCTAssertThrowsError(
            try OpenRouterAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"error":{"message":"Provider disconnected unexpectedly"},"choices":[{"delta":{"content":""},"finish_reason":"error"}]}"#
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Provider disconnected unexpectedly")
        }
    }

    func testOpenRouterClientRejectsRelativeAPIBase() async {
        let client = OpenRouterAPIClient()

        do {
            _ = try await client.fetchModels(apiBase: "not-a-url", apiKey: "")
            XCTFail("Expected invalid API base error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid API Base: not-a-url")
        }
    }

    func testOpenRouterClientRejectsAPIBaseWithQuery() async {
        let client = OpenRouterAPIClient()

        do {
            _ = try await client.fetchModels(apiBase: "https://example.com/api?debug=true", apiKey: "")
            XCTFail("Expected invalid API base error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid API Base: https://example.com/api?debug=true")
        }
    }

}

private extension NSAttributedString {
    var containsTextAttachment: Bool {
        var foundAttachment = false
        enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: length)
        ) { value, _, stop in
            guard value is NSTextAttachment else {
                return
            }

            foundAttachment = true
            stop.pointee = true
        }
        return foundAttachment
    }

    func paragraphStyle(containing text: String) -> NSParagraphStyle? {
        let range = (string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            return nil
        }

        return attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }
}
