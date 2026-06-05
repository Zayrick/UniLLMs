//
//  OpenRouterAPIClientTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class OpenRouterAPIClientTests: XCTestCase {
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

    func testOpenRouterProviderRendersContextInstructionsAsSystemMessage() async throws {
        let capture = RequestCapture { request in
            try Self.doneStreamResponse(for: request)
        }
        let session = makeCapturingSession(capture: capture)
        let provider = OpenRouterProvider(apiClient: OpenRouterAPIClient(session: session))
        let prompt = makePrompt()
        let memory = makeMemory(text: "Use metric units.")
        defer {
            capture.invalidate()
        }

        var deltas: [ChatResponseDelta] = []
        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: "openai/gpt-4o-mini",
                messages: [makeTestChatMessage(role: .user, content: "Hello")],
                context: ChatContext(
                    systemPrompt: prompt,
                    memories: [memory]
                )
            ),
            configuration: provider.defaultConfiguration
        ) {
            deltas.append(delta)
        }

        XCTAssertTrue(deltas.isEmpty)
        let requests = capture.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        let requestMessages = try Self.chatRequestMessages(from: request)
        XCTAssertEqual(requestMessages.map { $0["role"] as? String }, ["system", "user"])
        let systemMessage = try XCTUnwrap(requestMessages.first)
        let userMessage = try XCTUnwrap(requestMessages.dropFirst().first)
        let systemContent = try XCTUnwrap(systemMessage["content"] as? String)
        XCTAssertTrue(systemContent.hasPrefix("Always answer in Chinese.\n\nmemories:\n"))
        XCTAssertTrue(systemContent.contains("\n-"))
        XCTAssertTrue(systemContent.contains("Use metric units."))
        XCTAssertEqual(userMessage["content"] as? String, "Hello")
    }

    func testOpenRouterProviderRequiresToolCapableRoutingWhenSendingTools() async throws {
        let capture = RequestCapture { request in
            try Self.doneStreamResponse(for: request)
        }
        let session = makeCapturingSession(capture: capture)
        let provider = OpenRouterProvider(apiClient: OpenRouterAPIClient(session: session))
        let tool = ToolDefinition(
            name: "get_weather",
            summary: "Get the current weather.",
            parameters: .emptyObjectSchema
        )
        defer {
            capture.invalidate()
        }

        for try await _ in provider.streamChat(
            request: ChatRequest(
                modelID: "openai/gpt-4o-mini",
                messages: [makeTestChatMessage(role: .user, content: "Weather?")],
                context: ChatContext(availableTools: [tool])
            ),
            configuration: provider.defaultConfiguration
        ) {}

        let request = try XCTUnwrap(capture.requests.first)
        let payload = try Self.chatRequestPayload(from: request)
        let providerPreferences = try XCTUnwrap(payload["provider"] as? [String: Any])
        XCTAssertEqual(providerPreferences["require_parameters"] as? Bool, true)
        XCTAssertNotNil(payload["tools"])
    }

    func testOpenRouterProviderSendsChatSessionIDAsOpenRouterSessionID() async throws {
        let capture = RequestCapture { request in
            try Self.doneStreamResponse(for: request)
        }
        let session = makeCapturingSession(capture: capture)
        let provider = OpenRouterProvider(apiClient: OpenRouterAPIClient(session: session))
        let chatSessionID = try XCTUnwrap(UUID(uuidString: "2F0D942C-77F0-4308-86B8-B3010E8D1378"))
        defer {
            capture.invalidate()
        }

        for try await _ in provider.streamChat(
            request: ChatRequest(
                modelID: "openai/gpt-4o-mini",
                messages: [makeTestChatMessage(role: .user, content: "Hello")],
                context: ChatContext(
                    session: makeTestChatSession(id: chatSessionID),
                    messages: [makeTestChatMessage(role: .user, content: "Hello")]
                )
            ),
            configuration: provider.defaultConfiguration
        ) {}

        let request = try XCTUnwrap(capture.requests.first)
        let payload = try Self.chatRequestPayload(from: request)
        XCTAssertEqual(
            payload["session_id"] as? String,
            "chat-2f0d942c-77f0-4308-86b8-b3010e8d1378"
        )
    }

    func testOpenAICompatibleProviderRendersContextInstructionsAsSystemMessage() async throws {
        let capture = RequestCapture { request in
            try Self.doneStreamResponse(for: request)
        }
        let session = makeCapturingSession(capture: capture)
        let provider = OpenAICompatibleProvider(apiClient: OpenAICompatibleAPIClient(session: session))
        let prompt = makePrompt()
        var configuration = provider.defaultConfiguration
        configuration[OpenAICompatibleProvider.ConfigurationKey.apiBase] = "https://api.example.com/v1"
        defer {
            capture.invalidate()
        }

        var deltas: [ChatResponseDelta] = []
        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: "test-model",
                messages: [makeTestChatMessage(role: .user, content: "Hello")],
                context: ChatContext(systemPrompt: prompt)
            ),
            configuration: configuration
        ) {
            deltas.append(delta)
        }

        XCTAssertTrue(deltas.isEmpty)
        let requests = capture.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        let requestMessages = try Self.chatRequestMessages(from: request)
        XCTAssertEqual(requestMessages.map { $0["role"] as? String }, ["system", "user"])
        let systemMessage = try XCTUnwrap(requestMessages.first)
        let userMessage = try XCTUnwrap(requestMessages.dropFirst().first)
        XCTAssertEqual(systemMessage["content"] as? String, "Always answer in Chinese.")
        XCTAssertEqual(userMessage["content"] as? String, "Hello")
    }

    func testOpenAIProviderRendersContextInstructionsAsSystemMessage() async throws {
        let capture = RequestCapture { request in
            try Self.doneStreamResponse(for: request)
        }
        let session = makeCapturingSession(capture: capture)
        let provider = OpenAIProvider(apiClient: OpenAIAPIClient(session: session))
        let prompt = makePrompt()
        defer {
            capture.invalidate()
        }

        for try await _ in provider.streamChat(
            request: ChatRequest(
                modelID: "gpt-5.4",
                messages: [makeTestChatMessage(role: .user, content: "Hello")],
                context: ChatContext(systemPrompt: prompt)
            ),
            configuration: provider.defaultConfiguration
        ) {}

        let request = try XCTUnwrap(capture.requests.first)
        let requestMessages = try Self.chatRequestMessages(from: request)
        XCTAssertEqual(requestMessages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(requestMessages.first?["content"] as? String, "Always answer in Chinese.")
    }

    func testOpenAICompatibleProviderRejectsFileAttachmentsBeforeSendingRequest() async throws {
        let capture = RequestCapture { request in
            XCTFail("File attachments should be rejected before a request is sent.")
            return try Self.doneStreamResponse(for: request)
        }
        let session = makeCapturingSession(capture: capture)
        let provider = OpenAICompatibleProvider(apiClient: OpenAICompatibleAPIClient(session: session))
        var configuration = provider.defaultConfiguration
        configuration[OpenAICompatibleProvider.ConfigurationKey.apiBase] = "https://api.example.com/v1"
        let attachment = ChatAttachment(
            kind: .file,
            filename: "notes.pdf",
            contentType: "application/pdf",
            relativePath: "missing-notes.pdf"
        )
        defer {
            capture.invalidate()
        }

        do {
            for try await _ in provider.streamChat(
                request: ChatRequest(
                    modelID: "test-model",
                    messages: [
                        makeTestChatMessage(
                            role: .user,
                            content: "Summarize this.",
                            attachments: [attachment]
                        )
                    ],
                    context: ChatContext()
                ),
                configuration: configuration
            ) {}
            XCTFail("Expected file attachment rejection.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "File attachments are not supported by OpenAI Compatible."
            )
        }

        XCTAssertTrue(capture.requests.isEmpty)
    }

    func testOpenRouterChatMessageEncodesAssistantToolCallsWithNullContent() throws {
        let message = try OpenRouterChatMessage(
            message: makeTestChatMessage(
                role: .assistant,
                content: "",
                toolCalls: [
                    ChatToolCall(
                        id: "call_1",
                        toolID: "lookup",
                        arguments: "{}"
                    )
                ]
            )
        )

        let data = try JSONEncoder().encode(message)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertTrue(payload["content"] is NSNull)
        XCTAssertEqual(payload["role"] as? String, "assistant")
        XCTAssertNotNil(payload["tool_calls"])
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

    func testOpenRouterClientFetchModelsUsesOfficialModelsEndpoint() async throws {
        let capture = RequestCapture { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://openrouter.ai/api/v1/models")
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
        let session = makeCapturingSession(capture: capture)
        let client = OpenRouterAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        let models = try await client.fetchModels(
            apiBase: " https://openrouter.ai/api/v1/ ",
            apiKey: " sk-or-test "
        )

        XCTAssertEqual(capture.requests.count, 1)
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

    func testOpenAIClientFetchModelsUsesStandardModelsEndpoint() async throws {
        let capture = RequestCapture { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = try XCTUnwrap(
                #"{"object":"list","data":[{"id":"gpt-5.4","object":"model","owned_by":"openai"}]}"#
                    .data(using: .utf8)
            )
            return (response, data)
        }
        let session = makeCapturingSession(capture: capture)
        let client = OpenAIAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        let models = try await client.fetchModels(
            apiBase: "https://api.openai.com/v1",
            apiKey: "sk-test"
        )

        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertEqual(models, [LLMsProviderModel(id: "gpt-5.4")])
    }

    func testOpenRouterClientFetchModelsOmitsAuthorizationWhenAPIKeyIsBlank() async throws {
        let capture = RequestCapture { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = try XCTUnwrap(#"{"data":[]}"#.data(using: .utf8))
            return (response, data)
        }
        let session = makeCapturingSession(capture: capture)
        let client = OpenRouterAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        let models = try await client.fetchModels(
            apiBase: "https://openrouter.ai/api/v1",
            apiKey: "   "
        )

        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertTrue(models.isEmpty)
    }

    func testOpenRouterClientFetchModelsIgnoresAdditionalOfficialModelFields() async throws {
        let capture = RequestCapture { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = try XCTUnwrap(
                """
                {
                    "data": [
                        {
                            "id": "openai/gpt-4",
                            "canonical_slug": "openai/gpt-4",
                            "name": "GPT-4",
                            "context_length": 8192,
                            "architecture": {
                                "modality": "text->text",
                                "input_modalities": ["text"],
                                "output_modalities": ["text"]
                            },
                            "pricing": {
                                "prompt": "0.00003",
                                "completion": "0.00006"
                            },
                            "supported_parameters": ["temperature", "top_p"],
                            "top_provider": {
                                "context_length": 8192
                            }
                        }
                    ]
                }
                """
                .data(using: .utf8)
            )
            return (response, data)
        }
        let session = makeCapturingSession(capture: capture)
        let client = OpenRouterAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        let models = try await client.fetchModels(
            apiBase: "https://openrouter.ai/api/v1",
            apiKey: "sk-or-test"
        )

        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertEqual(models, [
            LLMsProviderModel(id: "openai/gpt-4", name: "GPT-4", contextLength: 8192)
        ])
    }

    func testOpenRouterClientFetchModelsPropagatesServerStatusBody() async throws {
        let capture = RequestCapture { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = try XCTUnwrap(#"{"error":{"message":"Unauthorized"}}"#.data(using: .utf8))
            return (response, data)
        }
        let session = makeCapturingSession(capture: capture)
        let client = OpenRouterAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        do {
            _ = try await client.fetchModels(
                apiBase: "https://openrouter.ai/api/v1",
                apiKey: "sk-or-test"
            )
            XCTFail("Expected server status error.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                #"OpenRouter returned HTTP 401: {"error":{"message":"Unauthorized"}}"#
            )
        }
        XCTAssertEqual(capture.requests.count, 1)
    }

    func testOpenRouterClientFetchModelsThrowsForMalformedJSON() async throws {
        let capture = RequestCapture { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = try XCTUnwrap(#"{"data":"not an array"}"#.data(using: .utf8))
            return (response, data)
        }
        let session = makeCapturingSession(capture: capture)
        let client = OpenRouterAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        do {
            _ = try await client.fetchModels(
                apiBase: "https://openrouter.ai/api/v1",
                apiKey: "sk-or-test"
            )
            XCTFail("Expected decoding error.")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
        XCTAssertEqual(capture.requests.count, 1)
    }

    private func makeCapturingSession(capture: RequestCapture) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCapturingURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            RequestCapturingURLProtocol.captureIDHeader: capture.id
        ]
        return URLSession(configuration: configuration)
    }

    private func makePrompt() -> SystemPromptRecord {
        SystemPromptRecord(
            title: "Translator",
            content: "Always answer in Chinese.",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    private func makeMemory(
        scope: MemoryScope = .user,
        text: String,
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date? = nil
    ) -> MemoryRecord {
        MemoryRecord(
            scope: scope,
            text: text,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func chatRequestMessages(from request: URLRequest) throws -> [[String: Any]] {
        let payload = try chatRequestPayload(from: request)
        return try XCTUnwrap(payload["messages"] as? [[String: Any]])
    }

    private static func chatRequestPayload(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
    }

    private static func doneStreamResponse(
        for request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )
        )
        let data = try XCTUnwrap("data: [DONE]\n\n".data(using: .utf8))
        return (response, data)
    }
}

private final class RequestCapture {
    fileprivate let id = UUID().uuidString
    private let handler: RequestCapturingURLProtocol.RequestHandler
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []

    init(handler: @escaping RequestCapturingURLProtocol.RequestHandler) {
        self.handler = handler
        RequestCapturingURLProtocol.register(capture: self, id: id)
    }

    var requests: [URLRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    func invalidate() {
        RequestCapturingURLProtocol.unregisterCapture(id: id)
    }

    fileprivate func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()

        return try handler(request)
    }
}

private final class RequestCapturingURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    fileprivate static let captureIDHeader = "X-UniLLMs-Test-Capture-ID"
    private static let lock = NSLock()
    private static var capturesByID: [String: RequestCapture] = [:]

    fileprivate static func register(capture: RequestCapture, id: String) {
        lock.lock()
        capturesByID[id] = capture
        lock.unlock()
    }

    fileprivate static func unregisterCapture(id: String) {
        lock.lock()
        capturesByID[id] = nil
        lock.unlock()
    }

    private static func capture(for id: String) -> RequestCapture? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturesByID[id]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let captureID = request.value(forHTTPHeaderField: Self.captureIDHeader),
              let capture = Self.capture(for: captureID) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try capture.handle(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
