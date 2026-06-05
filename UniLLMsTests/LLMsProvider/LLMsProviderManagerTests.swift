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
        let openRouterDefaultAPIBase = OpenRouterProvider().defaultConfiguration[OpenRouterProvider.ConfigurationKey.apiBase]

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

    func testProviderManagerCreatesPollinationsDraftFromRegisteredAdapter() throws {
        let manager = makeProviderManager(adapters: [PollinationsProvider()])
        let defaultAPIBase = PollinationsProvider().defaultConfiguration[PollinationsProvider.ConfigurationKey.apiBase]

        let draft = try manager.makeProviderDraft(kind: .pollinations)

        XCTAssertEqual(draft.kind, .pollinations)
        XCTAssertEqual(draft.name, "Pollinations")
        XCTAssertEqual(draft.configuration[PollinationsProvider.ConfigurationKey.apiBase], defaultAPIBase)
        XCTAssertEqual(draft.configuration[PollinationsProvider.ConfigurationKey.apiKey], "")
        XCTAssertTrue(draft.models.isEmpty)

        switch manager.modelSource(for: .pollinations) {
        case .some(.remote):
            break
        case .some(.manual), .some(.`static`), nil:
            XCTFail("Pollinations should fetch models remotely.")
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

    func testDefaultProviderCatalogRegistersNativeAndFallbackProviders() {
        let registry = LLMsProviderCatalog.makeRegistry()

        XCTAssertNotNil(registry.adapter(for: .openAI))
        XCTAssertNotNil(registry.adapter(for: .anthropic))
        XCTAssertNotNil(registry.adapter(for: .gemini))
        XCTAssertNotNil(registry.adapter(for: .pollinations))
        XCTAssertNotNil(registry.adapter(for: .openRouter))
        XCTAssertNotNil(registry.adapter(for: .openAICompatible))
        XCTAssertNotNil(registry.adapter(for: .fake))
    }

    func testDefaultProviderDraftUsesCatalogOrder() throws {
        let registry = LLMsProviderCatalog.makeRegistry()
        let manager = LLMsProviderManager(registry: registry, store: store)

        let draft = try manager.makeDefaultProviderDraft()

        XCTAssertEqual(draft.kind, .openRouter)
    }

    func testProviderManagerReportsToolCapabilityFromAdapter() throws {
        let manager = makeProviderManager(
            adapters: [
                OpenRouterProvider(),
                PollinationsProvider(),
                OpenAICompatibleProvider(),
                FakeLLMsProvider()
            ]
        )
        let openRouterProvider = try manager.makeProviderDraft(kind: .openRouter)
        var openAICompatibleProvider = try manager.makeProviderDraft(kind: .openAICompatible)
        let pollinationsProvider = try manager.makeProviderDraft(kind: .pollinations)
        let fakeProvider = try manager.makeProviderDraft(kind: .fake)

        XCTAssertTrue(manager.provider(openRouterProvider, supports: .tools))
        XCTAssertTrue(manager.provider(pollinationsProvider, supports: .tools))
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
        let openRouterDefaultAPIBase = OpenRouterProvider().defaultConfiguration[OpenRouterProvider.ConfigurationKey.apiBase]
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

    func testProviderManagerValidatesChatConfigurationThroughProviderAdapter() throws {
        let manager = makeProviderManager(adapters: [AnthropicProvider()])
        var provider = try manager.makeProviderDraft(kind: .anthropic)
        provider.configuration[AnthropicProvider.ConfigurationKey.apiKey] = "sk-ant-test"
        provider.configuration[AnthropicProvider.ConfigurationKey.maxTokens] = "not-a-number"

        XCTAssertTrue(manager.hasRequiredConfigurationFields(for: provider))
        XCTAssertThrowsError(try manager.validateChatConfiguration(for: provider)) { error in
            XCTAssertEqual(error as? AnthropicProviderError, .invalidMaxTokens)
        }

        provider.configuration[AnthropicProvider.ConfigurationKey.maxTokens] = "4096"

        XCTAssertNoThrow(try manager.validateChatConfiguration(for: provider))
    }

    func testProviderManagerValidatesRemoteModelConfigurationBeforeFetching() async throws {
        let adapter = ValidatingRemoteModelProvider()
        let manager = makeProviderManager(adapters: [adapter])
        var provider = try manager.makeProviderDraft(kind: ValidatingRemoteModelProvider.providerKind)

        do {
            _ = try await manager.fetchModels(for: provider)
            XCTFail("Expected remote model fetch to fail validation.")
        } catch {
            XCTAssertEqual(error as? ValidatingRemoteModelProviderError, .missingToken)
        }
        XCTAssertFalse(adapter.didFetchModels)

        provider.configuration[ValidatingRemoteModelProvider.ConfigurationKey.token] = "token"
        let models = try await manager.fetchModels(for: provider)

        XCTAssertEqual(models, [LLMProviderModel(id: "validated-model", name: "Validated Model")])
        XCTAssertTrue(adapter.didFetchModels)
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
        var provider = try addTestProvider()
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
        XCTAssertEqual(selection.providerName, "Test Remote")
        XCTAssertEqual(selection.modelName, "GPT-4.1")
    }
}

private enum ValidatingRemoteModelProviderError: LocalizedError, Equatable {
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Missing validation token."
        }
    }
}

private final class ValidatingRemoteModelProvider: LLMsProviderAdapter {
    static let providerKind = LLMsProviderKind(rawValue: "validatingRemoteModelProvider")

    enum ConfigurationKey {
        static let token = "token"
    }

    private(set) var didFetchModels = false

    var kind: LLMsProviderKind {
        Self.providerKind
    }

    var displayName: String {
        "Validating Remote Model Provider"
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.modelList, .streamingChat]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration(values: [ConfigurationKey.token: ""])
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .remote
    }

    func validateChatConfiguration(_ configuration: LLMsProviderConfiguration) throws {
        guard configuration[ConfigurationKey.token].isEmpty == false else {
            throw ValidatingRemoteModelProviderError.missingToken
        }
    }

    func fetchModels(configuration: LLMsProviderConfiguration) async throws -> [LLMsProviderModel] {
        didFetchModels = true
        return [LLMProviderModel(id: "validated-model", name: "Validated Model")]
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
