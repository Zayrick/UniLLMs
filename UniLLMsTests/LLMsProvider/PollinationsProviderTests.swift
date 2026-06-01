//
//  PollinationsProviderTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class PollinationsProviderTests: XCTestCase {
    func testPollinationsStreamParserDecodesContentReasoningAndToolCallDelta() throws {
        let delta = try XCTUnwrap(
            PollinationsAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"choices":[{"delta":{"content":"Hello","reasoning":"Thinking","tool_calls":[{"index":0,"id":"call_1","function":{"name":"search","arguments":"{\"query\":"}}]}}]}"#
            )
        )

        XCTAssertEqual(delta.content, "Hello")
        XCTAssertEqual(delta.reasoning, "Thinking")

        let toolCallDelta = try XCTUnwrap(delta.toolCallDeltas.first)
        XCTAssertEqual(toolCallDelta.index, 0)
        XCTAssertEqual(toolCallDelta.id, "call_1")
        XCTAssertEqual(toolCallDelta.name, "search")
        XCTAssertEqual(toolCallDelta.argumentsFragment, #"{"query":"#)
    }

    func testPollinationsStreamParserDecodesReasoningDetailsDelta() throws {
        let delta = try XCTUnwrap(
            PollinationsAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"choices":[{"delta":{"reasoning_details":[{"text":"Step "},{"summary":"summary"}]}}]}"#
            )
        )

        XCTAssertEqual(delta.content, "")
        XCTAssertEqual(delta.reasoning, "Step summary")
    }

    func testPollinationsStreamParserIgnoresCommentsAndDoneEvents() throws {
        XCTAssertNil(try PollinationsAPIClient.streamDelta(fromServerSentEventLine: ": ping"))
        XCTAssertNil(try PollinationsAPIClient.streamDelta(fromServerSentEventLine: "data: [DONE]"))
    }

    func testPollinationsStreamParserThrowsMidStreamError() throws {
        XCTAssertThrowsError(
            try PollinationsAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"error":{"message":"model unavailable"}}"#
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "model unavailable")
        }
    }

    func testPollinationsClientFetchModelsUsesFreeAnonymousEndpointWhenKeyBlank() async throws {
        let capture = PollinationsRequestCapture { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://text.pollinations.ai/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

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
                [
                    {
                        "name": "openai-fast",
                        "description": "GPT-OSS 20B Reasoning LLM",
                        "tier": "anonymous",
                        "input_modalities": ["text"],
                        "output_modalities": ["text"],
                        "tools": true,
                        "context_length": 64000
                    },
                    {
                        "name": "paid-text",
                        "description": "Paid text model",
                        "tier": "seed",
                        "input_modalities": ["text"],
                        "output_modalities": ["text"]
                    },
                    {
                        "name": "anonymous-image",
                        "description": "Anonymous image model",
                        "tier": "anonymous",
                        "input_modalities": ["text"],
                        "output_modalities": ["image"]
                    }
                ]
                """
                .data(using: .utf8)
            )
            return (response, data)
        }
        let session = makeCapturingSession(capture: capture)
        let client = PollinationsAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        let models = try await client.fetchModels(
            apiBase: " https://gen.pollinations.ai/v1/ ",
            apiKey: "   "
        )

        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertEqual(
            models,
            [
                LLMsProviderModel(
                    id: "openai-fast",
                    name: "GPT-OSS 20B Reasoning LLM",
                    contextLength: 64_000
                )
            ]
        )
    }

    func testPollinationsClientFetchModelsSendsAuthorizationWhenKeyIsPresent() async throws {
        let capture = PollinationsRequestCapture { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-pollinations-test")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = try XCTUnwrap(#"{"object":"list","data":[]}"#.data(using: .utf8))
            return (response, data)
        }
        let session = makeCapturingSession(capture: capture)
        let client = PollinationsAPIClient(session: session)
        defer {
            capture.invalidate()
        }

        let models = try await client.fetchModels(
            apiBase: "https://gen.pollinations.ai/v1",
            apiKey: " sk-pollinations-test "
        )

        XCTAssertTrue(models.isEmpty)
        XCTAssertEqual(capture.requests.count, 1)
    }

    func testPollinationsProviderStreamsWithoutAPIKeyUsingFreeChatCompletionsEndpoint() async throws {
        let capture = PollinationsRequestCapture { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://text.pollinations.ai/openai/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let payload = try Self.chatRequestPayload(from: request)
            XCTAssertEqual(payload["model"] as? String, "openai-fast")
            XCTAssertEqual(payload["stream"] as? Bool, true)

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
        let session = makeCapturingSession(capture: capture)
        let provider = PollinationsProvider(apiClient: PollinationsAPIClient(session: session))
        defer {
            capture.invalidate()
        }

        for try await _ in provider.streamChat(
            request: ChatRequest(
                modelID: "openai-fast",
                messages: [ChatMessage(role: .user, content: "Hello")],
                context: ChatContext()
            ),
            configuration: provider.defaultConfiguration
        ) {}

        XCTAssertEqual(capture.requests.count, 1)
    }

    func testPollinationsProviderStreamsWithAPIKeyUsingOfficialV1ChatCompletionsEndpoint() async throws {
        let capture = PollinationsRequestCapture { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://gen.pollinations.ai/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-pollinations-test")

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
        let session = makeCapturingSession(capture: capture)
        let provider = PollinationsProvider(apiClient: PollinationsAPIClient(session: session))
        var configuration = provider.defaultConfiguration
        configuration[PollinationsProvider.ConfigurationKey.apiKey] = " sk-pollinations-test "
        defer {
            capture.invalidate()
        }

        for try await _ in provider.streamChat(
            request: ChatRequest(
                modelID: "openai",
                messages: [ChatMessage(role: .user, content: "Hello")],
                context: ChatContext()
            ),
            configuration: configuration
        ) {}

        XCTAssertEqual(capture.requests.count, 1)
    }

    func testPollinationsProviderDoesNotRequireAPIKeyOrCustomAPIBase() throws {
        let provider = PollinationsProvider()
        var configuration = provider.defaultConfiguration

        XCTAssertNoThrow(try provider.validateChatConfiguration(configuration))

        configuration[PollinationsProvider.ConfigurationKey.apiBase] = ""

        XCTAssertNoThrow(try provider.validateChatConfiguration(configuration))
    }

    func testPollinationsServerStatusDescriptionsCoverQuotaAndRateLimit() {
        XCTAssertEqual(
            PollinationsAPIClient.APIError.serverStatus(
                "Pollinations",
                402,
                #"{"error":"empty"}"#
            )
            .localizedDescription,
            #"Pollinations returned HTTP 402: {"error":"empty"}. Pollen balance or API key budget is exhausted."#
        )

        XCTAssertEqual(
            PollinationsAPIClient.APIError.serverStatus("Pollinations", 429, nil).localizedDescription,
            "Pollinations returned HTTP 429. Rate limit exceeded."
        )
    }

    private func makeCapturingSession(capture: PollinationsRequestCapture) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PollinationsRequestCapturingURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            PollinationsRequestCapturingURLProtocol.captureIDHeader: capture.id
        ]
        return URLSession(configuration: configuration)
    }

    private static func chatRequestPayload(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
    }
}

private final class PollinationsRequestCapture {
    fileprivate let id = UUID().uuidString
    private let handler: PollinationsRequestCapturingURLProtocol.RequestHandler
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []

    init(handler: @escaping PollinationsRequestCapturingURLProtocol.RequestHandler) {
        self.handler = handler
        PollinationsRequestCapturingURLProtocol.register(capture: self, id: id)
    }

    var requests: [URLRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    func invalidate() {
        PollinationsRequestCapturingURLProtocol.unregisterCapture(id: id)
    }

    fileprivate func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()

        return try handler(request)
    }
}

private final class PollinationsRequestCapturingURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    fileprivate static let captureIDHeader = "X-UniLLMs-Pollinations-Test-Capture-ID"
    private static let lock = NSLock()
    private static var capturesByID: [String: PollinationsRequestCapture] = [:]

    fileprivate static func register(capture: PollinationsRequestCapture, id: String) {
        lock.lock()
        capturesByID[id] = capture
        lock.unlock()
    }

    fileprivate static func unregisterCapture(id: String) {
        lock.lock()
        capturesByID[id] = nil
        lock.unlock()
    }

    private static func capture(for id: String) -> PollinationsRequestCapture? {
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
