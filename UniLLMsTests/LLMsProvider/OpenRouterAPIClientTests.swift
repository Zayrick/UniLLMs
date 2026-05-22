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

    func testOpenRouterClientFetchModelsOmitsAuthorizationWhenAPIKeyIsBlank() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenRouterAPIClient(session: session)

        RequestCapturingURLProtocol.requestHandler = { request in
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
        defer {
            RequestCapturingURLProtocol.requestHandler = nil
        }

        let models = try await client.fetchModels(
            apiBase: "https://openrouter.ai/api/v1",
            apiKey: "   "
        )

        XCTAssertTrue(models.isEmpty)
    }

    func testOpenRouterClientFetchModelsIgnoresAdditionalOfficialModelFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenRouterAPIClient(session: session)

        RequestCapturingURLProtocol.requestHandler = { request in
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
        defer {
            RequestCapturingURLProtocol.requestHandler = nil
        }

        let models = try await client.fetchModels(
            apiBase: "https://openrouter.ai/api/v1",
            apiKey: "sk-or-test"
        )

        XCTAssertEqual(models, [
            LLMsProviderModel(id: "openai/gpt-4", name: "GPT-4", contextLength: 8192)
        ])
    }

    func testOpenRouterClientFetchModelsPropagatesServerStatusBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenRouterAPIClient(session: session)

        RequestCapturingURLProtocol.requestHandler = { request in
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
        defer {
            RequestCapturingURLProtocol.requestHandler = nil
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
    }

    func testOpenRouterClientFetchModelsThrowsForMalformedJSON() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenRouterAPIClient(session: session)

        RequestCapturingURLProtocol.requestHandler = { request in
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
        defer {
            RequestCapturingURLProtocol.requestHandler = nil
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
