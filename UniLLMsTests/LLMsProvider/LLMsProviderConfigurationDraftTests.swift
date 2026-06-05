//
//  LLMsProviderConfigurationDraftTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class LLMsProviderConfigurationDraftTests: XCTestCase {
    func testFieldValuesReadAndWriteProviderNameAndConfigurationValues() {
        var draft = LLMsProviderConfigurationDraft(
            provider: makeProvider(),
            modelSource: .remote
        )
        let nameField = makeField(binding: .providerName)
        let apiKeyField = makeField(binding: .configurationValue("apiKey"))

        draft.setValue("Team Router", for: nameField)
        draft.setValue("sk-test", for: apiKeyField)

        XCTAssertEqual(draft.value(for: nameField), "Team Router")
        XCTAssertEqual(draft.value(for: apiKeyField), "sk-test")
        XCTAssertTrue(draft.hasUnsavedChanges)
    }

    func testBooleanValueAcceptsCommonTruthyValues() {
        let field = makeField(
            binding: .configurationValue("toolsEnabled"),
            inputKind: .toggle
        )
        var draft = LLMsProviderConfigurationDraft(
            provider: makeProvider(configuration: ["toolsEnabled": " YES "]),
            modelSource: .manual
        )

        XCTAssertTrue(draft.booleanValue(for: field))

        draft.setValue("off", for: field)

        XCTAssertFalse(draft.booleanValue(for: field))
    }

    func testBlankManualModelRowDoesNotCreateUnsavedChangesAfterNormalization() {
        var draft = LLMsProviderConfigurationDraft(
            provider: makeProvider(),
            modelSource: .manual
        )

        draft.appendManualModel()

        XCTAssertEqual(draft.manualModelCount, 0)
        XCTAssertFalse(draft.hasUnsavedChanges)
        XCTAssertFalse(
            draft.canSave(
                isNewProvider: false,
                hasRequiredConfigurationFields: true
            )
        )
    }

    func testManualModelSavingTrimsIDsDropsBlankRowsAndUpdatesTimestampWhenListChanges() {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = LLMsProviderConfigurationDraft(
            provider: makeProvider(),
            modelSource: .manual
        )

        let firstIndex = draft.appendManualModel()
        XCTAssertTrue(draft.setManualModelID("  llama3.1  ", at: firstIndex))
        draft.appendManualModel()

        var namedProvider = draft.provider
        namedProvider.models[firstIndex].name = "  Local Llama  "
        draft = LLMsProviderConfigurationDraft(
            provider: namedProvider,
            savedProvider: makeProvider(),
            modelSource: .manual
        )

        let providerForSaving = draft.providerForSaving(updatedAt: updatedAt)

        XCTAssertEqual(
            providerForSaving.models,
            [
                LLMsProviderModel(
                    id: "llama3.1",
                    name: "Local Llama",
                    contextLength: nil
                )
            ]
        )
        XCTAssertEqual(providerForSaving.modelsUpdatedAt, updatedAt)
        XCTAssertTrue(draft.hasUnsavedChanges)
    }

    func testManualProviderComparisonIgnoresModelsUpdatedAtWhenModelsAreUnchanged() {
        let savedAt = Date(timeIntervalSince1970: 100)
        let currentAt = Date(timeIntervalSince1970: 200)
        let models = [LLMsProviderModel(id: "model-a", name: "Model A")]
        let savedProvider = makeProvider(models: models, modelsUpdatedAt: savedAt)
        let currentProvider = makeProvider(models: models, modelsUpdatedAt: currentAt)
        let draft = LLMsProviderConfigurationDraft(
            provider: currentProvider,
            savedProvider: savedProvider,
            modelSource: .manual
        )

        XCTAssertFalse(draft.hasUnsavedChanges)
    }

    func testRemoteModelReplacementMarksModelsAsSaved() {
        let updatedAt = Date(timeIntervalSince1970: 300)
        var draft = LLMsProviderConfigurationDraft(
            provider: makeProvider(),
            modelSource: .remote
        )

        draft.replaceRemoteModels(
            [LLMsProviderModel(id: "openai/gpt-4.1-mini", name: "GPT-4.1 mini")],
            updatedAt: updatedAt
        )

        XCTAssertEqual(draft.provider.models.count, 1)
        XCTAssertEqual(draft.provider.modelsUpdatedAt, updatedAt)
        XCTAssertFalse(draft.hasUnsavedChanges)
    }

    func testModelPresentationUsesTrimmedNameWhenAvailable() {
        let draft = LLMsProviderConfigurationDraft(
            provider: makeProvider(),
            modelSource: .remote
        )
        let namedModel = LLMsProviderModel(id: "model-a", name: "  Model A  ")
        let unnamedModel = LLMsProviderModel(id: "model-b", name: "   ")

        XCTAssertEqual(draft.modelTitle(for: namedModel), "Model A")
        XCTAssertEqual(draft.modelSubtitle(for: namedModel), "model-a")
        XCTAssertEqual(draft.modelTitle(for: unnamedModel), "model-b")
        XCTAssertNil(draft.modelSubtitle(for: unnamedModel))
    }

    private func makeProvider(
        configuration: [String: String] = [:],
        models: [LLMsProviderModel] = [],
        modelsUpdatedAt: Date? = nil
    ) -> LLMsProviderRecord {
        LLMsProviderRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .openAICompatible,
            name: "OpenAI Compatible",
            configuration: LLMsProviderConfiguration(values: configuration),
            models: models,
            modelsUpdatedAt: modelsUpdatedAt,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeField(
        binding: LLMsProviderConfigurationField.Binding,
        inputKind: LLMsProviderConfigurationField.InputKind = .plain
    ) -> LLMsProviderConfigurationField {
        LLMsProviderConfigurationField(
            id: UUID().uuidString,
            title: "Field",
            placeholder: "",
            binding: binding,
            inputKind: inputKind
        )
    }
}
