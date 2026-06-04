//
//  OpenRouterAPIClient.swift
//  UniLLMs
//
//  OpenRouter-specific wrapper around shared OpenAI-compatible Chat Completions support.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

typealias OpenRouterMessageContent = OpenAICompatibleMessageContent
typealias OpenRouterContentPart = OpenAICompatibleContentPart
typealias OpenRouterChatMessage = OpenAICompatibleChatMessage
typealias OpenRouterChatTool = OpenAICompatibleChatTool
typealias OpenRouterToolCallDelta = OpenAICompatibleToolCallDelta
typealias OpenRouterChatStreamDelta = OpenAICompatibleChatStreamDelta

nonisolated struct OpenRouterAPIClient {
    typealias APIError = OpenAICompatibleAPIClient.APIError

    nonisolated private static let defaultServiceName = "OpenRouter"
    nonisolated private static let defaultAPIBaseValue = "https://openrouter.ai/api/v1"

    private var client: OpenAICompatibleAPIClient

    var session: URLSession {
        get {
            client.session
        }
        set {
            client.session = newValue
        }
    }

    var serviceName: String {
        get {
            client.serviceName
        }
        set {
            client.serviceName = newValue
        }
    }

    var defaultAPIBase: String {
        get {
            client.defaultAPIBase
        }
        set {
            client.defaultAPIBase = newValue
        }
    }

    init(
        session: URLSession = .shared,
        serviceName: String = Self.defaultServiceName,
        defaultAPIBase: String = Self.defaultAPIBaseValue
    ) {
        client = OpenAICompatibleAPIClient(
            session: session,
            serviceName: serviceName,
            defaultAPIBase: defaultAPIBase
        )
    }

    func streamChatCompletion(
        apiBase: String,
        apiKey: String,
        model: String,
        messages: [OpenRouterChatMessage],
        tools: [OpenRouterChatTool] = [],
        sessionID: String? = nil
    ) -> AsyncThrowingStream<OpenRouterChatStreamDelta, Error> {
        client.streamChatCompletion(
            apiBase: apiBase,
            apiKey: apiKey,
            model: model,
            messages: messages,
            tools: tools,
            providerPreferences: tools.isEmpty
                ? nil
                : OpenAICompatibleChatProviderPreferences(requireParameters: true),
            sessionID: sessionID,
            authorizationPolicy: .omitWhenBlank,
            includesReasoningDetails: true,
            fallbackToolCallIDPrefix: "tool_call_"
        )
    }

    func fetchModels(
        apiBase: String,
        apiKey: String
    ) async throws -> [LLMsProviderModel] {
        try await client.fetchModels(
            apiBase: apiBase,
            apiKey: apiKey,
            includeModelMetadata: true,
            authorizationPolicy: .omitWhenBlank
        )
    }

    nonisolated static func streamDelta(
        fromServerSentEventLine line: String,
        serviceName: String = defaultServiceName
    ) throws -> OpenRouterChatStreamDelta? {
        try OpenAICompatibleAPIClient.streamDelta(
            fromServerSentEventLine: line,
            serviceName: serviceName,
            includesReasoningDetails: true
        )
    }
}
