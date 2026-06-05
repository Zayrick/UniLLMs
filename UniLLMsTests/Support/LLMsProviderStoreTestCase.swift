//
//  LLMsProviderStoreTestCase.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

class LLMsProviderStoreTestCase: UserDefaultsBackedTestCase {
    var store: LLMProviderStore!
    var notificationCenter: NotificationCenter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        notificationCenter = NotificationCenter()
        store = LLMProviderStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "providers"
        )
    }

    override func tearDownWithError() throws {
        store = nil
        notificationCenter = nil
        try super.tearDownWithError()
    }

    func makeProviderManager(
        adapters: [any LLMsProviderAdapter]? = nil
    ) -> LLMsProviderManager {
        LLMsProviderManager(
            registry: LLMsProviderRegistry(adapters: adapters ?? [TestRemoteProvider()]),
            store: store
        )
    }

    func makeTestProviderDraft() throws -> LLMsProviderRecord {
        try makeProviderManager().makeProviderDraft(kind: TestRemoteProvider.providerKind)
    }

    @discardableResult
    func addTestProvider() throws -> LLMsProviderRecord {
        let provider = try makeTestProviderDraft()
        store.saveProvider(provider)
        return provider
    }

    var testProviderDefaultAPIBase: String {
        TestRemoteProvider().defaultConfiguration[TestRemoteProvider.ConfigurationKey.apiBase]
    }
}

nonisolated struct TestRemoteProvider: LLMsProviderAdapter {
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

func makeTestChatSession(
    id: UUID = UUID(),
    title: String = "",
    createdAt: Date = Date(timeIntervalSince1970: 1),
    updatedAt: Date = Date(timeIntervalSince1970: 1),
    selectedSystemPromptID: UUID? = nil
) -> ChatSession {
    ChatSession(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        selectedSystemPromptID: selectedSystemPromptID
    )
}

func makeTestChatMessage(
    id: UUID = UUID(),
    role: ChatRole,
    content: String,
    reasoning: String = "",
    toolCalls: [ChatToolCall]? = nil,
    toolCallID: String? = nil,
    toolDisplayName: String? = nil,
    toolStatus: ToolExecutionStatus? = nil,
    attachments: [ChatAttachment] = [],
    createdAt: Date = Date(timeIntervalSince1970: 1)
) -> ChatMessage {
    ChatMessage(
        id: id,
        role: role,
        content: content,
        reasoning: reasoning,
        toolCalls: toolCalls,
        toolCallID: toolCallID,
        toolDisplayName: toolDisplayName,
        toolStatus: toolStatus,
        attachments: attachments,
        createdAt: createdAt
    )
}
