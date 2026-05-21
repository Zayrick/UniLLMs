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
            case .codeBlock:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .mathBlock:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .table:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .image:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .details:
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
        XCTAssertEqual(draft.configuration[OpenAICompatibleProvider.ConfigurationKey.toolsEnabled], "false")
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

    func testBuiltInToolCatalogRegistersDateTimeTool() {
        let registry = BuiltInToolCatalog.makeRegistry()

        XCTAssertNotNil(registry.tool(id: "current_datetime"))
        XCTAssertEqual(registry.tools.map(\.definition.name), ["current_datetime"])
        XCTAssertEqual(registry.tools.first?.definition.symbolName, "clock")
    }

    func testProviderManagerReportsToolCapabilityFromAdapter() throws {
        let manager = makeProviderManager()
        let openRouterProvider = try manager.makeProviderDraft(kind: .openRouter)
        var openAICompatibleProvider = try manager.makeProviderDraft(kind: .openAICompatible)
        let fakeProvider = try manager.makeProviderDraft(kind: .fake)

        XCTAssertTrue(manager.provider(openRouterProvider, supports: .tools))
        XCTAssertFalse(manager.provider(openAICompatibleProvider, supports: .tools))

        openAICompatibleProvider.configuration[OpenAICompatibleProvider.ConfigurationKey.toolsEnabled] = "true"

        XCTAssertTrue(manager.provider(openAICompatibleProvider, supports: .tools))
        XCTAssertFalse(manager.provider(fakeProvider, supports: .tools))
    }

    func testToolCatalogExposesBuiltInToolsWhenEnabled() async {
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { true }
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertEqual(definitions.map(\.name), ["current_datetime"])
        XCTAssertEqual(definitions.first?.presentationName, "Current Date and Time")
    }

    func testToolCatalogReturnsNoToolsWhenDisabled() async {
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { false }
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertTrue(definitions.isEmpty)
        XCTAssertNil(catalog.tool(id: "current_datetime"))
    }

    func testToolCatalogSkipsDisabledBuiltInTools() async {
        let catalog = ToolCatalog(
            registry: ToolRegistry(tools: [DateTimeTool()]),
            isEnabled: { true },
            isRegisteredToolEnabled: { $0 != "current_datetime" }
        )

        let definitions = await catalog.loadAvailableTools()

        XCTAssertTrue(definitions.isEmpty)
        XCTAssertNil(catalog.tool(id: "current_datetime"))
    }

    func testMCPToolResultPreservesExecutionErrorStatus() {
        let result = MCPHTTPClient.toolResult(
            from: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Invalid search query.")
                    ])
                ]),
                "isError": .bool(true)
            ])
        )

        XCTAssertEqual(result.content, "Invalid search query.")
        XCTAssertTrue(result.isError)
    }

    func testChatTurnRunnerMapsErrorToolResultToFailedToolEvent() async throws {
        let providerManager = makeProviderManager(adapters: [ToolLoopTestProvider()])
        let runner = ChatTurnRunner(
            responseStreamer: ChatResponseStreamer(providerManager: providerManager),
            toolManager: ToolManager(
                catalog: ToolCatalog(
                    registry: ToolRegistry(tools: [ErrorStatusTool()]),
                    isEnabled: { true }
                )
            )
        )
        let provider = LLMsProviderRecord(
            kind: ToolLoopTestProvider.providerKind,
            name: "Tool Loop Test",
            configuration: LLMsProviderConfiguration()
        )
        let tool = ErrorStatusTool()
        let context = ChatContext(
            session: ChatSession(title: "Tool Error"),
            messages: [
                ChatMessage(role: .user, content: "Use the failing tool.")
            ],
            availableTools: [tool.definition]
        )

        var toolEvents: [ChatToolEvent] = []
        var content = ""
        for try await event in runner.streamResponse(
            provider: provider,
            modelID: "test-model",
            context: context
        ) {
            switch event {
            case let .displayDelta(delta):
                content += delta.content
                for part in delta.displayParts {
                    if case let .toolEvent(toolEvent) = part {
                        toolEvents.append(toolEvent)
                    }
                }
            case .timelineEvent:
                continue
            }
        }

        XCTAssertEqual(content, "Recovered after tool error.")
        XCTAssertEqual(toolEvents.count, 2)
        guard let firstEvent = toolEvents.first,
              case let .started(startedCall) = firstEvent else {
            XCTFail("Expected a started tool event.")
            return
        }
        guard let lastEvent = toolEvents.last,
              case let .failed(failedCall, message) = lastEvent else {
            XCTFail("Expected a failed tool event.")
            return
        }
        XCTAssertEqual(startedCall.id, "call_1")
        XCTAssertEqual(failedCall.id, "call_1")
        XCTAssertEqual(failedCall.presentationName, "Failing Tool")
        XCTAssertEqual(message, "Invalid tool input.")
    }

    @MainActor
    func testThinkingSectionHeaderKeepsProcessingStatusAndShowsFinishedCounts() {
        let section = ThinkingSectionView()

        XCTAssertEqual(section.firstLabelText, "Processing")

        section.appendReasoning("Need data.")
        section.appendToolInvocation(
            callID: "call_1",
            displayName: "Weather Search",
            state: .running
        )

        XCTAssertEqual(section.firstLabelText, "Processing")

        section.appendToolInvocation(
            callID: "call_1",
            displayName: "Weather Search",
            state: .completed
        )
        section.appendReasoning("Use the result.")
        section.setThinking(false, animated: false)

        XCTAssertEqual(section.firstLabelText, "2 reasoning steps, 1 tool call")
        XCTAssertFalse(section.containsLabelText("Thought process"))
    }

    @MainActor
    func testThinkingSectionFinishedHeaderOmitsZeroCounts() {
        let reasoningOnlySection = ThinkingSectionView()
        reasoningOnlySection.appendReasoning("Need data.")
        reasoningOnlySection.setThinking(false, animated: false)

        XCTAssertEqual(reasoningOnlySection.firstLabelText, "1 reasoning step")

        let toolOnlySection = ThinkingSectionView()
        toolOnlySection.appendToolInvocation(
            callID: "call_1",
            displayName: "Weather Search",
            state: .completed
        )
        toolOnlySection.setThinking(false, animated: false)

        XCTAssertEqual(toolOnlySection.firstLabelText, "1 tool call")

        let emptySection = ThinkingSectionView()
        emptySection.setThinking(false, animated: false)

        XCTAssertTrue(emptySection.isHidden)
    }

    func testToolSettingsStorePersistsGlobalAndBuiltInToolEnablement() {
        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "toolSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )

        XCTAssertFalse(settingsStore.loadToolsEnabled())
        XCTAssertTrue(settingsStore.isBuiltInToolEnabled(id: "current_datetime"))

        settingsStore.saveToolsEnabled(true)
        settingsStore.saveBuiltInToolEnabled(false, id: "current_datetime")

        let reloadedStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "toolSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )

        XCTAssertTrue(reloadedStore.loadToolsEnabled())
        XCTAssertFalse(reloadedStore.isBuiltInToolEnabled(id: "current_datetime"))

        reloadedStore.saveBuiltInToolEnabled(true, id: "current_datetime")

        XCTAssertTrue(reloadedStore.isBuiltInToolEnabled(id: "current_datetime"))
    }

    func testToolSettingsStoreReadsLegacyMCPGlobalToolsEnabled() throws {
        let legacyJSON = #"{"toolsEnabled":true,"servers":[]}"#
        defaults.set(try XCTUnwrap(legacyJSON.data(using: .utf8)), forKey: "legacyMCPSettings")

        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "missingToolSettings",
            legacyMCPStorageKey: "legacyMCPSettings"
        )

        XCTAssertTrue(settingsStore.loadToolsEnabled())

        let migratedStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "missingToolSettings",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )

        XCTAssertTrue(migratedStore.loadToolsEnabled())
    }

    func testMCPServerStorePersistsServers() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        var server = mcpStore.makeServerDraft()
        XCTAssertEqual(server.name, "")

        server.name = "Team Tools"
        server.configuration = MCPServerConfiguration(
            endpoint: "https://example.com/mcp",
            headers: ["Authorization": "Bearer test"],
            timeout: 30,
            isEnabled: true
        )

        mcpStore.saveServerRecord(server)

        let reloadedStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        let reloadedServer = reloadedStore.loadServers().first

        XCTAssertEqual(reloadedServer?.id, server.id)
        XCTAssertEqual(reloadedServer?.name, "Team Tools")
        XCTAssertEqual(reloadedServer?.configuration.endpoint, "https://example.com/mcp")
        XCTAssertEqual(reloadedServer?.configuration.headers["Authorization"], "Bearer test")
        XCTAssertEqual(reloadedServer?.configuration.timeout, 30)
        XCTAssertEqual(reloadedServer?.configuration.isEnabled, true)
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

    func testMarkdownInlineCodeUsesRoundedPillAttributesWithoutTextPadding() throws {
        let attributedText = renderMarkdownText("Use `let value = 1` now")
        let codeRange = try XCTUnwrap(attributedText.range(of: "let value = 1"))

        XCTAssertEqual(attributedText.string, "Use let value = 1 now")
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
        let cornerRadius = try XCTUnwrap(
            attributedText.attribute(
                .chatInlineCodeCornerRadius,
                at: codeRange.location,
                effectiveRange: nil
            ) as? CGFloat
        )
        XCTAssertEqual(cornerRadius, ChatMarkdownInlineCodeStyle.cornerRadius)
        XCTAssertNil(
            attributedText.attribute(
                .backgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            )
        )
    }

    func testMarkdownInlineCodeAddsOuterMarginWhenAdjacentToText() {
        let attributedText = renderMarkdownText("A`code`B")

        XCTAssertEqual(attributedText.string, "A code B")
    }

    func testMarkdownNestedStrongEmphasisCombinesFontTraits() throws {
        let attributedText = renderMarkdownText("***Bold italic***")
        let font = try XCTUnwrap(attributedText.font(containing: "Bold italic"))
        let traits = font.fontDescriptor.symbolicTraits

        XCTAssertTrue(traits.contains(.traitBold))
        XCTAssertTrue(traits.contains(.traitItalic))
    }

    func testMarkdownNestedInlineCodePreservesOuterModes() throws {
        let attributedText = renderMarkdownText("[**`id`**](https://example.com)")
        let codeRange = try XCTUnwrap(attributedText.range(of: "id"))
        let font = try XCTUnwrap(
            attributedText.attribute(.font, at: codeRange.location, effectiveRange: nil) as? UIFont
        )

        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(
            attributedText.attribute(.link, at: codeRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://example.com")
        )
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownInlineLatexRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Euler has $e^{i\\pi}+1=0$ inline.")

        XCTAssertTrue(attributedText.string.contains("Euler has "))
        XCTAssertTrue(attributedText.string.contains(" inline."))
        XCTAssertFalse(attributedText.string.contains("$e^{i\\pi}+1=0$"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownInlineChemistryLatexRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Water is $\\ce{H2O}$ and sulfate is $\\ce{SO4^2-}$.")

        XCTAssertTrue(attributedText.string.contains("Water is "))
        XCTAssertTrue(attributedText.string.contains(" and sulfate is "))
        XCTAssertFalse(attributedText.string.contains("\\ce{H2O}"))
        XCTAssertFalse(attributedText.string.contains("\\ce{SO4^2-}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 2)
    }

    func testMarkdownBareChemistryCommandRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Balanced reaction: \\ce{2H2 + O2 -> 2H2O}.")

        XCTAssertTrue(attributedText.string.contains("Balanced reaction: "))
        XCTAssertFalse(attributedText.string.contains("\\ce{2H2 + O2 -> 2H2O}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownExtensibleArrowLatexRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Catalyst $A \\xrightarrow[heat]{Pt} B$ done.")

        XCTAssertTrue(attributedText.string.contains("Catalyst "))
        XCTAssertTrue(attributedText.string.contains(" done."))
        XCTAssertFalse(attributedText.string.contains("\\xrightarrow[heat]{Pt}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownChemistryArrowLabelsRenderAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Labeled reaction: \\ce{A ->[H2O][heat] B}.")

        XCTAssertTrue(attributedText.string.contains("Labeled reaction: "))
        XCTAssertFalse(attributedText.string.contains("\\ce{A ->[H2O][heat] B}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownChemistryNuclideNotationRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Nuclide: \\ce{^{227}_{90}Th+}.")

        XCTAssertTrue(attributedText.string.contains("Nuclide: "))
        XCTAssertFalse(attributedText.string.contains("\\ce{^{227}_{90}Th+}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownChemistryPhysicalUnitsRenderAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Heat capacity: \\pu{75.3 J // mol K}; concentration: \\pu{1.2e-3 mol L-1}.")

        XCTAssertTrue(attributedText.string.contains("Heat capacity: "))
        XCTAssertFalse(attributedText.string.contains("\\pu{75.3 J // mol K}"))
        XCTAssertFalse(attributedText.string.contains("\\pu{1.2e-3 mol L-1}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 2)
    }

    func testMarkdownChemistryComplexMhchemExamplesRenderAsInlineAttachments() throws {
        let attributedText = renderMarkdownText(
            "Examples: \\ce{Zn^2+ <=>[+ 2OH-][+ 2H+] Zn(OH)2 v}, \\ce{A\\bond{#}B}, \\ce{NaOH(aq,$\\infty$)}."
        )

        XCTAssertTrue(attributedText.string.contains("Examples: "))
        XCTAssertEqual(attributedText.textAttachmentCount, 3)
    }

    func testMarkdownEscapedDollarDoesNotStartInlineLatex() {
        let attributedText = renderMarkdownText("Price is \\$5 and math is $x+1$.")

        XCTAssertTrue(attributedText.string.contains("$5"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownDisplayLatexRendersAsDedicatedBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Before

            $$
            \\frac{a}{b}=c
            $$

            After
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text, display math, and text blocks")
            return
        }
        guard case let .text(beforeText) = blocks[0] else {
            XCTFail("Expected leading text block")
            return
        }
        guard case let .mathBlock(mathBlock) = blocks[1] else {
            XCTFail("Expected display math block")
            return
        }
        guard case let .text(afterText) = blocks[2] else {
            XCTFail("Expected trailing text block")
            return
        }

        XCTAssertEqual(beforeText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Before")
        XCTAssertEqual(mathBlock.latex, "\\frac{a}{b}=c")
        XCTAssertEqual(afterText.string.trimmingCharacters(in: .whitespacesAndNewlines), "After")
    }

    func testMarkdownDisplayChemistryLatexRendersAsDedicatedBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Reaction

            $$
            \\ce{2H2 + O2 -> 2H2O}
            $$
            """
        )

        guard blocks.count == 2 else {
            XCTFail("Expected text and display chemistry blocks")
            return
        }
        guard case let .mathBlock(mathBlock) = blocks[1] else {
            XCTFail("Expected display chemistry block")
            return
        }

        XCTAssertEqual(mathBlock.latex, "\\ce{2H2 + O2 -> 2H2O}")
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

    func testMarkdownCodeBlockRendersAsDedicatedBlockWithLanguageFallback() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Intro

            ```swift
            let value = 1
            ```

            ```
            plain
            ```
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text and two code blocks")
            return
        }
        guard case let .text(introText) = blocks[0] else {
            XCTFail("Expected leading text block")
            return
        }
        guard case let .codeBlock(swiftCodeBlock) = blocks[1] else {
            XCTFail("Expected Swift code block")
            return
        }
        guard case let .codeBlock(fallbackCodeBlock) = blocks[2] else {
            XCTFail("Expected fallback code block")
            return
        }

        XCTAssertEqual(introText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Intro")
        XCTAssertEqual(swiftCodeBlock.displayLanguage, "swift")
        XCTAssertEqual(swiftCodeBlock.code, "let value = 1")
        XCTAssertEqual(fallbackCodeBlock.displayLanguage, "Code")
        XCTAssertEqual(fallbackCodeBlock.code, "plain")
    }

    func testMarkdownStandaloneImageRendersAsDedicatedBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Intro

            ![Architecture](https://example.com/diagram.png)

            Outro
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text, image, and text blocks")
            return
        }
        guard case let .text(introText) = blocks[0] else {
            XCTFail("Expected leading text block")
            return
        }
        guard case let .image(imageBlock) = blocks[1] else {
            XCTFail("Expected standalone image block")
            return
        }
        guard case let .text(outroText) = blocks[2] else {
            XCTFail("Expected trailing text block")
            return
        }

        XCTAssertEqual(introText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Intro")
        XCTAssertEqual(imageBlock.source, "https://example.com/diagram.png")
        XCTAssertEqual(imageBlock.altText, "Architecture")
        XCTAssertEqual(outroText.string, "Outro")
    }

    func testMarkdownStreamSegmenterCompletesStableBlocksAndLeavesCurrentTail() {
        var segmenter = ChatMarkdownStreamSegmenter()

        var update = segmenter.append("# Title\n")
        XCTAssertEqual(update.completedSegments, ["# Title\n"])
        XCTAssertNil(update.currentSegment)

        update = segmenter.append("Intro")
        XCTAssertTrue(update.completedSegments.isEmpty)
        XCTAssertEqual(update.currentSegment, "Intro")

        update = segmenter.append("\n\n![Alt](https://example.com/image.png)\nNext")
        XCTAssertEqual(
            update.completedSegments,
            [
                "Intro\n",
                "![Alt](https://example.com/image.png)\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "Next")
    }

    func testMarkdownStreamSegmenterCompletesDisplayLatexBlock() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            $$
            x^2 + y^2 = z^2
            $$

            Next paragraph
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                """
                $$
                x^2 + y^2 = z^2
                $$
                """
            ]
        )
        XCTAssertEqual(update.currentSegment, "Next paragraph")
    }

    func testMarkdownStreamSegmenterKeepsBlockQuoteAsOutermostSegment() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            > Outer
            > still quoted

            Next
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                """
                > Outer
                > still quoted

                """
            ]
        )
        XCTAssertEqual(update.currentSegment, "Next")
    }

    func testMarkdownStreamSegmenterCompletesTableWhenNextSegmentStarts() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | Feature | Count |
            | :-- | --: |
            | Tables | 2 |
            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                """
                | Feature | Count |
                | :-- | --: |
                | Tables | 2 |
                """
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterKeepsHTMLDetailsAsOutermostSegment() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let detailsMarkdown = "<details>\n<summary>More</summary>\n\nInside **bold** body.\n\n</details>\n\nAfter"
        let update = segmenter.append(detailsMarkdown)

        XCTAssertEqual(
            update.completedSegments,
            ["<details>\n<summary>More</summary>\n\nInside **bold** body.\n\n</details>\n"]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotCompleteOpenHTMLDetailsBeforeClosingTag() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let detailsMarkdown = "<details>\n<summary>More</summary>\n\nInside **bold** body.\n"
        let update = segmenter.append(detailsMarkdown)

        XCTAssertTrue(update.completedSegments.isEmpty)
        XCTAssertEqual(update.currentSegment, detailsMarkdown)
    }

    func testMarkdownStreamSegmenterDoesNotTreatInlineDetailsTextAsHTMLBlock() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("The <details> tag is literal text.\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["The <details> tag is literal text.\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testIncrementalMarkdownLineParserKeepsStableIDWhilePartialLineGrows() throws {
        var parser = IncrementalMarkdownLineParser()

        let firstBlocks = parser.append("Hel")
        let firstBlock = try XCTUnwrap(firstBlocks.first)

        let secondBlocks = parser.append("lo")
        let secondBlock = try XCTUnwrap(secondBlocks.first)

        XCTAssertEqual(secondBlock.id, firstBlock.id)
        XCTAssertEqual(secondBlock.rawMarkdown, "Hello")
        XCTAssertFalse(secondBlock.isClosed)
    }

    func testIncrementalMarkdownLineParserDoesNotCommitSingleLineBlocksBeforeNewline() throws {
        var parser = IncrementalMarkdownLineParser()

        let draftBlocks = parser.append("---")
        let draftBlock = try XCTUnwrap(draftBlocks.first)
        XCTAssertEqual(draftBlock.kind, .textual)
        XCTAssertFalse(draftBlock.isClosed)

        let completedBlocks = parser.append("\n")
        let completedBlock = try XCTUnwrap(completedBlocks.first)
        XCTAssertEqual(completedBlock.id, draftBlock.id)
        XCTAssertEqual(completedBlock.kind, .thematicBreak)
        XCTAssertTrue(completedBlock.isClosed)
    }

    func testStreamingMarkdownTaskListUsesSymbolAttachmentBeforeLineCompletes() throws {
        let context = ChatMarkdownRenderingContext(style: .assistant, traitCollection: markdownRendererTraits)
        let rendered = StreamingMarkdownTextRenderer(context: context).render(rawMarkdown: "- [ ]", isOpen: true)

        let attachment = rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(attachment)
        XCTAssertFalse(rendered.string.contains("☐"))
    }

    func testStreamingMarkdownBlockQuoteKeepsContiguousLinesInOneParagraph() {
        let context = ChatMarkdownRenderingContext(style: .assistant, traitCollection: markdownRendererTraits)
        let rendered = StreamingMarkdownTextRenderer(context: context).render(
            rawMarkdown: """
            > first quoted line
            > second quoted line
            """,
            isOpen: true
        )

        XCTAssertEqual(rendered.string, "first quoted line second quoted line\n")
        XCTAssertNotNil(rendered.attribute(.chatBlockQuoteBarPositions, at: 0, effectiveRange: nil))
    }

    func testMarkdownTableInlineCodeUsesRoundedPillAttributesAndCleanAccessibilityText() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            | Code |
            | :-- |
            | `id` |
            """
        )

        let firstBlock = try XCTUnwrap(blocks.first)
        guard case let .table(tableData) = firstBlock else {
            XCTFail("Expected first rendered block to be a Markdown table")
            return
        }

        let codeCell = tableData.rows[1][0]
        let codeRange = try XCTUnwrap(codeCell.attributedText.range(of: "id"))

        XCTAssertEqual(codeCell.accessibilityText, "id")
        XCTAssertNotNil(
            codeCell.attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownTableNestedStrongEmphasisCombinesFontTraits() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            | Value |
            | :-- |
            | ***Cell*** |
            """
        )

        let firstBlock = try XCTUnwrap(blocks.first)
        guard case let .table(tableData) = firstBlock else {
            XCTFail("Expected first rendered block to be a Markdown table")
            return
        }

        let font = try XCTUnwrap(tableData.rows[1][0].attributedText.font(containing: "Cell"))
        let traits = font.fontDescriptor.symbolicTraits

        XCTAssertTrue(traits.contains(.traitBold))
        XCTAssertTrue(traits.contains(.traitItalic))
    }

    func testMarkdownBlockQuoteNestedInlineStylesCompose() throws {
        let attributedText = renderMarkdownText("> ***Quoted*** `id`")
        let quoteFont = try XCTUnwrap(attributedText.font(containing: "Quoted"))
        let quoteTraits = quoteFont.fontDescriptor.symbolicTraits
        let codeRange = try XCTUnwrap(attributedText.range(of: "id"))
        let paragraphStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Quoted"))

        XCTAssertTrue(quoteTraits.contains(.traitBold))
        XCTAssertTrue(quoteTraits.contains(.traitItalic))
        XCTAssertGreaterThan(paragraphStyle.headIndent, 0.0)
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
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

    func testMarkdownBlockQuoteStoresBarPositionAtLeadingMargin() throws {
        let attributedText = renderMarkdownText("> Quote")
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Quote"))

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0], ChatMarkdownBlockQuoteStyle.barLeading, accuracy: 0.001)
    }

    func testMarkdownNestedBlockQuoteStoresBarPositionForEachLevel() throws {
        let attributedText = renderMarkdownText("> Outer\n>\n> > Inner")
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Inner"))

        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0], ChatMarkdownBlockQuoteStyle.barLeading, accuracy: 0.001)
        XCTAssertEqual(
            positions[1],
            ChatMarkdownBlockQuoteStyle.barLeading + ChatMarkdownBlockQuoteStyle.indentPerLevel,
            accuracy: 0.001
        )
    }

    func testMarkdownListContinuationPreservesNestedBlockQuoteIndent() throws {
        let attributedText = renderMarkdownText("- Item\n  > Quote")

        let itemStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Item"))
        let quoteStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Quote"))

        XCTAssertGreaterThan(quoteStyle.firstLineHeadIndent, itemStyle.headIndent)
        XCTAssertGreaterThan(quoteStyle.headIndent, itemStyle.headIndent)
    }

    func testMarkdownListContinuationOffsetsNestedBlockQuoteBarPosition() throws {
        let attributedText = renderMarkdownText("- Item\n  > Quote")

        let itemStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Item"))
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Quote"))

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(
            positions[0],
            itemStyle.headIndent + ChatMarkdownBlockQuoteStyle.barLeading,
            accuracy: 0.001
        )
    }

    func testMarkdownBlockQuoteKeepsOuterBarBeforeNestedListMarker() throws {
        let attributedText = renderMarkdownText("> - Item")

        let itemStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Item"))
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Item"))

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0], ChatMarkdownBlockQuoteStyle.barLeading, accuracy: 0.001)
        XCTAssertGreaterThan(itemStyle.firstLineHeadIndent, positions[0])
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

    func testMarkdownInlineHTMLRendersGFMTextSemantics() throws {
        let attributedText = renderMarkdownText(
            "A <strong>bold</strong> <em>italic</em> <code>code</code> H<sub>2</sub>O x<sup>2</sup><br/>next"
        )

        XCTAssertEqual(attributedText.string, "A bold italic code H2O x2\nnext")
        XCTAssertTrue(try XCTUnwrap(attributedText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(try XCTUnwrap(attributedText.font(containing: "italic")).fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: try XCTUnwrap(attributedText.range(of: "code")).location,
                effectiveRange: nil
            ) as? UIColor
        )
        XCTAssertLessThan(
            try XCTUnwrap(attributedText.baselineOffset(containing: "2O")),
            0.0
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(attributedText.baselineOffset(containing: "2\n")),
            0.0
        )
    }

    func testMarkdownHTMLBlockRendersAllowedTagsAndFiltersDisallowedGFMRawHTML() throws {
        let attributedText = renderMarkdownText(
            """
            <dl>
              <dt>Definition title</dt>
              <dd>Definition body with <strong>strong HTML</strong>, <code>inline HTML code</code>, and &copy;.</dd>
            </dl>

            <script>alert(1)</script>
            """
        )

        XCTAssertTrue(attributedText.string.contains("Definition title"))
        XCTAssertTrue(attributedText.string.contains("Definition body with strong HTML, inline HTML code, and ©."))
        XCTAssertFalse(attributedText.string.contains("<dl>"))
        XCTAssertFalse(attributedText.string.contains("<strong>"))
        XCTAssertTrue(attributedText.string.contains("<script>"))
        XCTAssertTrue(attributedText.string.contains("</script>"))
        XCTAssertTrue(try XCTUnwrap(attributedText.font(containing: "strong HTML")).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: try XCTUnwrap(attributedText.range(of: "inline HTML code")).location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownHTMLBlockDecodesCommonNamedEntitiesWithoutHTMLImporter() {
        let attributedText = renderMarkdownText("Symbols: &copy; &trade; &mdash; &notareal;")

        XCTAssertEqual(attributedText.string, "Symbols: © ™ — &notareal;")
    }

    func testMarkdownHTMLTagFilterKeepsAllGFMDisallowedRawTagsLiteral() {
        let attributedText = renderMarkdownText(
            """
            <title>T</title>
            <textarea>T</textarea>
            <style>T</style>
            <xmp>T</xmp>
            <iframe>T</iframe>
            <noembed>T</noembed>
            <noframes>T</noframes>
            <script>T</script>
            <plaintext>T</plaintext>
            """
        )

        for tagName in ChatMarkdownHTMLSupport.disallowedRawHTMLTagNames {
            XCTAssertTrue(attributedText.string.contains("<\(tagName)>"))
            XCTAssertTrue(attributedText.string.contains("</\(tagName)>"))
        }
    }

    func testMarkdownHTMLTagFilterDoesNotRenderNestedTagsInsideDisallowedRawHTML() throws {
        let attributedText = renderMarkdownText(
            #"<script><strong>not bold</strong><img src="https://example.com/x.png"><details><summary>Hidden</summary></details></script>"#
        )

        XCTAssertTrue(attributedText.string.contains(#"<strong>not bold</strong>"#))
        XCTAssertTrue(attributedText.string.contains(#"<img src="https://example.com/x.png">"#))
        XCTAssertTrue(attributedText.string.contains("<details><summary>Hidden</summary></details>"))
        XCTAssertFalse(
            try XCTUnwrap(attributedText.font(containing: "not bold"))
                .fontDescriptor
                .symbolicTraits
                .contains(.traitBold)
        )
    }

    func testMarkdownHTMLCommentsAndCustomAnchorsDoNotRenderVisibleText() {
        let attributedText = renderMarkdownText(
            """
            Before
            <!-- hidden comment -->
            <a name="custom-anchor"></a>
            After
            """
        )

        XCTAssertTrue(attributedText.string.contains("Before"))
        XCTAssertTrue(attributedText.string.contains("After"))
        XCTAssertFalse(attributedText.string.contains("hidden comment"))
        XCTAssertFalse(attributedText.string.contains("custom-anchor"))
    }

    func testMarkdownStandaloneHTMLPictureRendersAsImageBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Intro

            <picture>
              <source media="(prefers-color-scheme: dark)" srcset="https://example.com/dark.png">
              <img alt="Diagram" src="https://example.com/default.png">
            </picture>

            Outro
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text, image, and text blocks")
            return
        }
        guard case let .image(imageBlock) = blocks[1] else {
            XCTFail("Expected HTML picture to render as an image block")
            return
        }

        XCTAssertEqual(imageBlock.source, "https://example.com/default.png")
        XCTAssertEqual(imageBlock.altText, "Diagram")
    }

    func testMarkdownWrappedStandaloneHTMLImageRendersAsImageBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: #"<p><img alt="Diagram" src="https://example.com/default.png"></p>"#
        )

        guard blocks.count == 1,
              case let .image(imageBlock) = blocks[0] else {
            XCTFail("Expected wrapped HTML image to render as an image block")
            return
        }

        XCTAssertEqual(imageBlock.source, "https://example.com/default.png")
        XCTAssertEqual(imageBlock.altText, "Diagram")
    }

    func testMarkdownHTMLTableRendersAsNativeTableBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Before

            <table>
              <thead>
                <tr><th>Name</th><th align="right">Score</th></tr>
              </thead>
              <tbody>
                <tr><td><strong>Ada</strong></td><td align="right">99</td></tr>
              </tbody>
            </table>

            After
            """
        )

        guard blocks.count == 3,
              case let .table(tableData) = blocks[1] else {
            XCTFail("Expected HTML table to render as a native table block")
            return
        }

        XCTAssertEqual(tableData.columnCount, 2)
        XCTAssertEqual(tableData.rows.count, 2)
        XCTAssertEqual(tableData.rows[0][0].accessibilityText, "Name")
        XCTAssertEqual(tableData.rows[0][1].accessibilityText, "Score")
        XCTAssertTrue(tableData.rows[0][0].isHeader)
        XCTAssertEqual(tableData.rows[0][1].alignment, .right)
        XCTAssertEqual(tableData.rows[1][0].accessibilityText, "Ada")
        XCTAssertTrue(try XCTUnwrap(tableData.rows[1][0].attributedText.font(containing: "Ada")).fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testMarkdownHTMLDetailsCreatesGitHubStyleDetailsBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            <summary><strong>More</strong> info</summary>

            Inside **bold** body.

            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0] else {
            XCTFail("Expected a single details block")
            return
        }
        guard detailsBlock.children.count == 1,
              case let .text(bodyText) = detailsBlock.children[0] else {
            XCTFail("Expected details body to render Markdown children")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "More info")
        XCTAssertFalse(detailsBlock.isOpen)
        XCTAssertEqual(bodyText.string, "Inside bold body.")
        XCTAssertTrue(try XCTUnwrap(bodyText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testMarkdownHTMLDetailsRendersBodyInOpeningHTMLBlock() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: #"""
            <details>
            <summary>More info</summary>
            Inside **bold** body.

            <p><img alt="Diagram" src="https://example.com/default.png"></p>

            </details>
            """#
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0] else {
            XCTFail("Expected a single details block")
            return
        }
        guard detailsBlock.children.count == 2,
              case let .text(bodyText) = detailsBlock.children[0],
              case let .image(imageBlock) = detailsBlock.children[1] else {
            XCTFail("Expected details body text and image to render as child blocks")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "More info")
        XCTAssertEqual(bodyText.string, "Inside bold body.")
        XCTAssertTrue(try XCTUnwrap(bodyText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(imageBlock.source, "https://example.com/default.png")
        XCTAssertEqual(imageBlock.altText, "Diagram")
    }

    func testMarkdownHTMLDetailsWithoutSummaryUsesDefaultSummaryAndKeepsBody() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            Body without summary.
            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0],
              detailsBlock.children.count == 1,
              case let .text(bodyText) = detailsBlock.children[0] else {
            XCTFail("Expected details body text")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "Details")
        XCTAssertEqual(bodyText.string, "Body without summary.")
    }

    func testMarkdownHTMLDetailsBodyPreservesMarkdownSourceBeforeNestedRendering() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            <summary>Escaped source</summary>
            Use &lt;tag&gt; &amp; **bold** text.
            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0],
              detailsBlock.children.count == 1,
              case let .text(bodyText) = detailsBlock.children[0] else {
            XCTFail("Expected details body text")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "Escaped source")
        XCTAssertEqual(bodyText.string, "Use <tag> & bold text.")
        XCTAssertTrue(try XCTUnwrap(bodyText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testMarkdownHTMLDetailsKeepsNestedDetailsInsideOuterBody() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            <summary>Outer</summary>

            Before

            <details><summary>Inner</summary>Inner body</details>

            After

            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(outerDetails) = blocks[0] else {
            XCTFail("Expected a single outer details block")
            return
        }
        guard outerDetails.children.count == 3,
              case let .text(beforeText) = outerDetails.children[0],
              case let .details(innerDetails) = outerDetails.children[1],
              case let .text(afterText) = outerDetails.children[2] else {
            XCTFail("Expected outer details to contain before text, nested details, and after text")
            return
        }
        guard innerDetails.children.count == 1,
              case let .text(innerText) = innerDetails.children[0] else {
            XCTFail("Expected inner details body text")
            return
        }

        XCTAssertEqual(outerDetails.summary, "Outer")
        XCTAssertEqual(beforeText.string, "Before")
        XCTAssertEqual(innerDetails.summary, "Inner")
        XCTAssertEqual(innerText.string, "Inner body")
        XCTAssertEqual(afterText.string, "After")
    }

    func testMarkdownHTMLOpenDetailsStartsExpanded() throws {
        var renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details open>
            <summary>Open section</summary>

            Body

            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0] else {
            XCTFail("Expected a details block")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "Open section")
        XCTAssertTrue(detailsBlock.isOpen)
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

    func testOpenRouterStreamParserDecodesToolCallDelta() throws {
        let delta = try XCTUnwrap(
            OpenRouterAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"mcp_abcd_search","arguments":"{\"query\":"}}]}}]}"#
            )
        )

        let toolCallDelta = try XCTUnwrap(delta.toolCallDeltas.first)
        XCTAssertEqual(toolCallDelta.index, 0)
        XCTAssertEqual(toolCallDelta.id, "call_1")
        XCTAssertEqual(toolCallDelta.name, "mcp_abcd_search")
        XCTAssertEqual(toolCallDelta.argumentsFragment, #"{"query":"#)
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

    func testOpenRouterClientFetchModelsUsesAuthenticatedUserModelsEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenRouterAPIClient(session: session)

        RequestCapturingURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://openrouter.ai/api/v1/models/user")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = try XCTUnwrap(
                #"{"data":[{"id":"openai/gpt-4o-mini","name":"GPT-4o mini","context_length":128000}]}"#
                    .data(using: .utf8)
            )
            return (response, data)
        }
        defer {
            RequestCapturingURLProtocol.requestHandler = nil
        }

        let models = try await client.fetchModels(
            apiBase: " https://openrouter.ai/api/v1/ ",
            apiKey: " sk-or-test "
        )

        XCTAssertEqual(
            models,
            [
                LLMsProviderModel(
                    id: "openai/gpt-4o-mini",
                    name: "GPT-4o mini",
                    contextLength: 128_000
                )
            ]
        )
    }

}

private final class RequestCapturingURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    static var requestHandler: RequestHandler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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

private struct ToolLoopTestProvider: LLMsProviderAdapter {
    static let providerKind = LLMsProviderKind(rawValue: "toolLoopTest")

    var kind: LLMsProviderKind {
        Self.providerKind
    }

    var displayName: String {
        "Tool Loop Test Provider"
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.streamingChat, .tools]
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
            if request.messages.contains(where: { $0.role == .tool }) {
                continuation.yield(ChatResponseDelta(content: "Recovered after tool error."))
            } else {
                continuation.yield(
                    ChatResponseDelta(
                        toolCalls: [
                            ChatToolCall(
                                id: "call_1",
                                toolID: ErrorStatusTool.toolID,
                                arguments: "{}"
                            )
                        ]
                    )
                )
            }
            continuation.finish()
        }
    }
}

private struct ErrorStatusTool: Tool {
    static let toolID = "failing_tool"

    let definition = ToolDefinition(
        name: ErrorStatusTool.toolID,
        displayName: "Failing Tool",
        summary: "Reports an execution error without throwing."
    )

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(
            callID: call.id,
            content: "Invalid tool input.",
            status: .error
        )
    }
}

private extension UIView {
    var firstLabelText: String? {
        recursiveLabels.first?.text
    }

    func containsLabelText(_ text: String) -> Bool {
        recursiveLabels.contains { $0.text == text }
    }

    var recursiveLabels: [UILabel] {
        let directLabels = subviews.compactMap { $0 as? UILabel }
        return directLabels + subviews.flatMap { $0.recursiveLabels }
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

    func range(of text: String) -> NSRange? {
        let range = (string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            return nil
        }

        return range
    }

    func font(containing text: String) -> UIFont? {
        guard let range = range(of: text) else {
            return nil
        }

        return attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
    }

    func baselineOffset(containing text: String) -> CGFloat? {
        guard let range = range(of: text) else {
            return nil
        }

        return attribute(.baselineOffset, at: range.location, effectiveRange: nil) as? CGFloat
    }

    func blockQuoteBarPositions(containing text: String) -> [CGFloat]? {
        guard let range = range(of: text) else {
            return nil
        }

        return attribute(
            .chatBlockQuoteBarPositions,
            at: range.location,
            effectiveRange: nil
        ) as? [CGFloat]
    }
}
