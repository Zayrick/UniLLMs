//
//  LLMsProviderManagerTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class LLMsProviderManagerTests: LLMsProviderStoreTestCase {
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
        let fetchedModels = try await manager.fetchModels(for: draft)

        XCTAssertEqual(fetchedModels, draft.models)

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
        let fetchedModels = try await manager.fetchModels(for: draft)

        XCTAssertEqual(fetchedModels, staticModels)

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
