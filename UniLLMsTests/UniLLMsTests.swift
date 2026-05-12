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

    private func makeProviderManager(
        adapters: [any LLMsProviderAdapter] = LLMsProviderCatalog.makeRegistry().adapters
    ) -> LLMsProviderManager {
        LLMsProviderManager(
            registry: LLMsProviderRegistry(adapters: adapters),
            store: store
        )
    }

    private func makeOpenRouterProviderDraft() throws -> LLMsProviderRecord {
        try makeProviderManager().makeProviderDraft(kind: .openRouter)
    }

    private func addOpenRouterProvider() throws -> LLMsProviderRecord {
        let provider = try makeOpenRouterProviderDraft()
        store.saveProvider(provider)
        return provider
    }

    private var openRouterDefaultAPIBase: String {
        OpenRouterProvider().defaultConfiguration[OpenRouterProvider.ConfigurationKey.apiBase]
    }

    private func renderMarkdownText(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> NSAttributedString {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: markdown)
        let result = NSMutableAttributedString()

        for block in blocks {
            switch block {
            case let .text(text):
                result.append(text)
            case .table:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            }
        }

        return result
    }

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

    func testProviderManagerCreatesOpenRouterDraftFromRegisteredAdapter() throws {
        let manager = makeProviderManager(adapters: [OpenRouterProvider()])

        let draft = try manager.makeProviderDraft(kind: .openRouter)

        XCTAssertEqual(draft.kind, .openRouter)
        XCTAssertEqual(draft.name, "OpenRouter")
        XCTAssertEqual(draft.configuration[OpenRouterProvider.ConfigurationKey.apiBase], openRouterDefaultAPIBase)
        XCTAssertTrue(draft.models.isEmpty)

        switch manager.modelSource(for: .openRouter) {
        case .some(.remote):
            break
        case .some(.manual), .some(.`static`), nil:
            XCTFail("OpenRouter should fetch models remotely.")
        }
    }

    func testProviderManagerCreatesOpenAICompatibleDraftFromRegisteredAdapter() throws {
        let manager = makeProviderManager(adapters: [OpenAICompatibleProvider()])

        let draft = try manager.makeProviderDraft(kind: .openAICompatible)

        XCTAssertEqual(draft.kind, .openAICompatible)
        XCTAssertEqual(draft.name, "OpenAI Compatible")
        XCTAssertEqual(draft.configuration[OpenAICompatibleProvider.ConfigurationKey.apiBase], "")
        XCTAssertEqual(draft.configuration[OpenAICompatibleProvider.ConfigurationKey.apiKey], "")
        XCTAssertTrue(draft.models.isEmpty)

        switch manager.modelSource(for: .openAICompatible) {
        case .some(.manual):
            break
        case .some(.remote), .some(.`static`), nil:
            XCTFail("OpenAI Compatible should use manual model entry.")
        }
    }

    func testProviderManagerCreatesFakeDraftWithBuiltInModelsAndNoConfiguration() async throws {
        let manager = makeProviderManager(adapters: [FakeLLMsProvider()])

        let draft = try manager.makeProviderDraft(kind: .fake)

        XCTAssertEqual(draft.kind, .fake)
        XCTAssertEqual(draft.name, "Fake")
        XCTAssertEqual(draft.configuration, LLMsProviderConfiguration())
        XCTAssertTrue(manager.configurationFields(for: .fake).isEmpty)
        XCTAssertTrue(manager.hasRequiredConfigurationFields(for: draft))
        XCTAssertEqual(
            draft.models,
            [
                LLMProviderModel(id: FakeLLMsProvider.ModelID.staticResponse, name: "Static"),
                LLMProviderModel(id: FakeLLMsProvider.ModelID.stream, name: "Stream"),
                LLMProviderModel(id: FakeLLMsProvider.ModelID.markdownStatic, name: "Markdown Static"),
                LLMProviderModel(id: FakeLLMsProvider.ModelID.markdownStream, name: "Markdown Stream")
            ]
        )
        XCTAssertEqual(try await manager.fetchModels(for: draft), draft.models)

        switch manager.modelSource(for: .fake) {
        case .some(.`static`):
            break
        case .some(.remote), .some(.manual), nil:
            XCTFail("Fake provider should use built-in models.")
        }
    }

    func testDefaultProviderCatalogRegistersFakeProvider() {
        let registry = LLMsProviderCatalog.makeRegistry()

        XCTAssertNotNil(registry.adapter(for: .fake))
    }

    func testFakeStaticModelReturnsSingleDelayedResponse() async throws {
        let provider = FakeLLMsProvider(staticResponseDelayNanoseconds: 0)
        var deltas: [ChatResponseDelta] = []

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.staticResponse,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            deltas.append(delta)
        }

        XCTAssertEqual(deltas.count, 1)
        XCTAssertTrue(deltas[0].content.contains("fake static response"))
    }

    func testFakeStreamModelYieldsResponseOneCharacterAtATime() async throws {
        let provider = FakeLLMsProvider(
            streamInitialDelayNanoseconds: 0,
            streamCharacterDelayNanoseconds: 0
        )
        var streamedContent = ""

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.stream,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            XCTAssertLessThanOrEqual(delta.content.count, 1)
            streamedContent += delta.content
        }

        XCTAssertTrue(streamedContent.contains("fake streaming response"))
    }

    func testFakeMarkdownStaticModelReturnsSingleMarkdownFixture() async throws {
        let provider = FakeLLMsProvider(staticResponseDelayNanoseconds: 0)
        var deltas: [ChatResponseDelta] = []

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.markdownStatic,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            deltas.append(delta)
        }

        XCTAssertEqual(deltas.count, 1)
        XCTAssertTrue(deltas[0].content.contains("# UniLLMs Markdown Torture Fixture"))
        XCTAssertTrue(deltas[0].content.contains("> [!NOTE]"))
        XCTAssertTrue(deltas[0].content.contains("```swift"))
        XCTAssertTrue(deltas[0].content.contains("$$"))
    }

    func testFakeMarkdownStreamModelYieldsMarkdownFixtureInRandomSizedCharacterChunks() async throws {
        let provider = FakeLLMsProvider(
            streamInitialDelayNanoseconds: 0,
            markdownStreamChunkDelayRangeNanoseconds: 0...0
        )
        var deltas: [ChatResponseDelta] = []
        var streamedContent = ""

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.markdownStream,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            deltas.append(delta)
            XCTAssertGreaterThanOrEqual(delta.content.count, 1)
            XCTAssertLessThanOrEqual(delta.content.count, 6)
            streamedContent += delta.content
        }

        XCTAssertGreaterThan(deltas.count, 10)
        XCTAssertTrue(streamedContent.contains("# UniLLMs Markdown Torture Fixture"))
        XCTAssertTrue(streamedContent.contains("| Feature | Syntax | Expected Alignment | Notes |"))
        XCTAssertTrue(streamedContent.contains("```mermaid"))
        XCTAssertTrue(streamedContent.contains("\\begin{bmatrix}"))
    }

    func testProviderManagerCreatesStaticDraftWithBuiltInModels() async throws {
        let staticModels = [
            LLMProviderModel(id: "openai/gpt-4.1-mini", name: "GPT-4.1 mini"),
            LLMProviderModel(id: "custom-model")
        ]
        let manager = makeProviderManager(
            adapters: [
                StaticModelProvider(staticModels: staticModels)
            ]
        )

        let draft = try manager.makeProviderDraft(kind: StaticModelProvider.providerKind)

        XCTAssertEqual(draft.kind, StaticModelProvider.providerKind)
        XCTAssertEqual(draft.name, "Static Test Provider")
        XCTAssertEqual(draft.models, staticModels)
        XCTAssertNil(draft.modelsUpdatedAt)
        XCTAssertNil(draft.models[1].name)
        XCTAssertEqual(try await manager.fetchModels(for: draft), staticModels)

        switch manager.modelSource(for: StaticModelProvider.providerKind) {
        case .some(.`static`):
            break
        case .some(.remote), .some(.manual), nil:
            XCTFail("Static test provider should use built-in models.")
        }
    }

    func testProviderManagerChecksOnlyRequiredConfigurationFields() throws {
        let manager = makeProviderManager(
            adapters: [
                OpenRouterProvider(),
                OpenAICompatibleProvider()
            ]
        )
        var openRouter = try manager.makeProviderDraft(kind: .openRouter)

        XCTAssertFalse(manager.hasRequiredConfigurationFields(for: openRouter))

        openRouter.configuration[OpenRouterProvider.ConfigurationKey.apiKey] = "sk-or-test"
        openRouter.configuration[OpenRouterProvider.ConfigurationKey.apiBase] = ""

        XCTAssertFalse(manager.hasRequiredConfigurationFields(for: openRouter))

        openRouter.configuration[OpenRouterProvider.ConfigurationKey.apiBase] = openRouterDefaultAPIBase
        openRouter.name = ""

        XCTAssertTrue(manager.hasRequiredConfigurationFields(for: openRouter))

        var compatible = try manager.makeProviderDraft(kind: .openAICompatible)

        XCTAssertFalse(manager.hasRequiredConfigurationFields(for: compatible))

        compatible.configuration[OpenAICompatibleProvider.ConfigurationKey.apiBase] = "http://localhost:11434/v1"
        compatible.configuration[OpenAICompatibleProvider.ConfigurationKey.apiKey] = ""

        XCTAssertTrue(manager.hasRequiredConfigurationFields(for: compatible))
    }

    func testProviderManagerRejectsUnregisteredProviderKind() throws {
        let manager = makeProviderManager(adapters: [])

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

    func testProviderManagerResolvesSelectedProviderDisplayNameFromRegisteredAdapter() throws {
        let manager = makeProviderManager()
        var provider = try addOpenRouterProvider()
        provider.name = ""
        provider.models = [
            LLMProviderModel(id: "openai/gpt-4.1", name: "GPT-4.1", contextLength: 1_000_000)
        ]
        store.updateProvider(provider)
        store.saveSelectedModelSelection(
            LLMModelSelection(
                providerID: provider.id,
                providerName: "Stale Name",
                modelID: "openai/gpt-4.1",
                modelName: "Stale Model Name"
            )
        )

        let selection = try XCTUnwrap(manager.fetchSelectedModelSelection())
        XCTAssertEqual(selection.providerName, "OpenRouter")
        XCTAssertEqual(selection.modelName, "GPT-4.1")
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

    func testMarkdownThematicBreakRendersAsVisualDivider() throws {
        let attributedText = renderMarkdownText("Above\n\n---\n\nBelow")

        XCTAssertFalse(attributedText.string.contains("---"))
        XCTAssertTrue(attributedText.string.contains("Above"))
        XCTAssertTrue(attributedText.string.contains("Below"))
        XCTAssertTrue(attributedText.containsTextAttachment)
    }

    func testMarkdownTableRendersAsDedicatedBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            | Feature | Count |
            | :-- | --: |
            | **Tables** | 2 |
            """
        )

        let firstBlock = try XCTUnwrap(blocks.first)
        guard case let .table(tableData) = firstBlock else {
            XCTFail("Expected first rendered block to be a Markdown table")
            return
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(tableData.columnCount, 2)
        XCTAssertEqual(tableData.rows.count, 2)
        XCTAssertEqual(tableData.rows[0][0].accessibilityText, "Feature")
        XCTAssertEqual(tableData.rows[1][0].accessibilityText, "Tables")
    }

    func testMarkdownNestedListRendersIncreasingIndents() throws {
        let attributedText = renderMarkdownText("- Parent\n  - Child\n    - Grandchild")

        let parentStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Parent"))
        let childStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Child"))
        let grandchildStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Grandchild"))

        XCTAssertGreaterThan(childStyle.firstLineHeadIndent, parentStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(grandchildStyle.firstLineHeadIndent, childStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(childStyle.headIndent, parentStyle.headIndent)
        XCTAssertGreaterThan(grandchildStyle.headIndent, childStyle.headIndent)
    }

    func testMarkdownBlockQuotePreservesNestedListIndents() throws {
        let attributedText = renderMarkdownText("> - Parent\n>   - Child\n>     - Grandchild")

        let parentStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Parent"))
        let childStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Child"))
        let grandchildStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Grandchild"))

        XCTAssertGreaterThan(childStyle.firstLineHeadIndent, parentStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(grandchildStyle.firstLineHeadIndent, childStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(childStyle.headIndent, parentStyle.headIndent)
        XCTAssertGreaterThan(grandchildStyle.headIndent, childStyle.headIndent)
    }

    func testMarkdownNestedBlockQuoteRendersIncreasingIndents() throws {
        let attributedText = renderMarkdownText("> Outer\n>\n> > Inner")

        let outerStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Outer"))
        let innerStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Inner"))

        XCTAssertGreaterThan(innerStyle.firstLineHeadIndent, outerStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(innerStyle.headIndent, outerStyle.headIndent)
    }

    func testMarkdownListContinuationPreservesNestedBlockQuoteIndent() throws {
        let attributedText = renderMarkdownText("- Item\n  > Quote")

        let itemStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Item"))
        let quoteStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Quote"))

        XCTAssertGreaterThan(quoteStyle.firstLineHeadIndent, itemStyle.headIndent)
        XCTAssertGreaterThan(quoteStyle.headIndent, itemStyle.headIndent)
    }

    func testMarkdownOrderedListUsesStableContentIndentAcrossDigitWidths() throws {
        let attributedText = renderMarkdownText("9. Nine\n10. Ten")

        let nineStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Nine"))
        let tenStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Ten"))

        XCTAssertEqual(nineStyle.headIndent, tenStyle.headIndent)
    }

    func testMarkdownTaskListRendersCheckboxMarkers() throws {
        let attributedText = renderMarkdownText("- [x] Done\n- [ ] Todo")

        XCTAssertEqual(attributedText.textAttachmentCount, 2)
        XCTAssertTrue(attributedText.string.contains("Done"))
        XCTAssertTrue(attributedText.string.contains("Todo"))
        XCTAssertFalse(attributedText.string.contains("[x]"))
        XCTAssertFalse(attributedText.string.contains("[ ]"))
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

    func testOpenRouterStreamParserUsesServiceNameForInvalidPayload() throws {
        XCTAssertThrowsError(
            try OpenRouterAPIClient.streamDelta(
                fromServerSentEventLine: "data: {",
                serviceName: "OpenAI Compatible"
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "OpenAI Compatible returned an invalid response.")
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

private struct StaticModelProvider: LLMsProviderAdapter {
    static let providerKind = LLMsProviderKind(rawValue: "staticTest")

    var staticModels: [LLMsProviderModel]

    var kind: LLMsProviderKind {
        Self.providerKind
    }

    var displayName: String {
        "Static Test Provider"
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.modelList, .streamingChat]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration()
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .`static`
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

private extension NSAttributedString {
    var containsTextAttachment: Bool {
        textAttachmentCount > 0
    }

    var textAttachmentCount: Int {
        var attachmentCount = 0
        enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: length)
        ) { value, _, _ in
            guard value is NSTextAttachment else {
                return
            }

            attachmentCount += 1
        }
        return attachmentCount
    }

    func paragraphStyle(containing text: String) -> NSParagraphStyle? {
        let range = (string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            return nil
        }

        return attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }
}
