//
//  NetworkRequestToolTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class NetworkRequestToolTests: XCTestCase {
    func testNetworkRequestToolExecutesGetWithQueryAndHeaders() async throws {
        let capture = NetworkRequestCapture { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.scheme, "http")
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertEqual(request.url?.path, "/api")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name, $0) }
                }),
                [
                    "existing": "1",
                    "page": "2",
                    "q": "hello world"
                ]
            )

            return try Self.response(
                request: request,
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: #"{"ok":true}"#
            )
        }
        let session = makeCapturingSession(capture: capture)
        defer {
            capture.invalidate()
            session.invalidateAndCancel()
        }

        let result = try await NetworkRequestTool(session: session).execute(
            call: ToolCall(
                id: "call_get",
                toolID: NetworkToolCatalog.requestID,
                arguments: [
                    "url": .string("http://127.0.0.1/api?existing=1"),
                    "headers": .object([
                        "Accept": .string("application/json")
                    ]),
                    "query": .object([
                        "page": .int(2),
                        "q": .string("hello world")
                    ])
                ]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertFalse(result.isError)
        let payload = try Self.payload(from: result)
        XCTAssertEqual(payload["status_code"] as? Int, 200)
        XCTAssertEqual(payload["body"] as? String, #"{"ok":true}"#)
        XCTAssertEqual(payload["body_encoding"] as? String, "utf-8")
        XCTAssertEqual(payload["truncated"] as? Bool, false)
        XCTAssertEqual(capture.requests.count, 1)
    }

    func testNetworkRequestToolExecutesPostWithJSONBody() async throws {
        let capture = NetworkRequestCapture { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/users")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Trace-ID"), "abc123")

            let body = try XCTUnwrap(request.httpBody)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["name"] as? String, "Alice")
            XCTAssertEqual(payload["active"] as? Bool, true)

            return try Self.response(
                request: request,
                statusCode: 201,
                headers: ["Content-Type": "text/plain"],
                body: "created"
            )
        }
        let session = makeCapturingSession(capture: capture)
        defer {
            capture.invalidate()
            session.invalidateAndCancel()
        }

        let result = try await NetworkRequestTool(session: session).execute(
            call: ToolCall(
                id: "call_post",
                toolID: NetworkToolCatalog.requestID,
                arguments: [
                    "method": .string("post"),
                    "url": .string("https://example.com/users"),
                    "headers": .object([
                        "X-Trace-ID": .string("abc123")
                    ]),
                    "body": .object([
                        "name": .string("Alice"),
                        "active": .bool(true)
                    ])
                ]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertFalse(result.isError)
        let payload = try Self.payload(from: result)
        XCTAssertEqual(payload["status_code"] as? Int, 201)
        XCTAssertEqual(payload["body"] as? String, "created")
    }

    func testNetworkRequestToolRejectsUnsupportedScheme() async throws {
        let result = try await NetworkRequestTool().execute(
            call: ToolCall(
                id: "call_ftp",
                toolID: NetworkToolCatalog.requestID,
                arguments: ["url": .string("ftp://example.com/file.txt")]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("ftp"))
    }

    func testNetworkRequestApprovalDetailsShowRequestAndRedactSensitiveHeaders() async throws {
        let provider = NetworkToolApprovalRequestProvider()
        let call = ToolCall(
            id: "call_approval",
            toolID: NetworkToolCatalog.requestID,
            arguments: [
                "method": .string("POST"),
                "url": .string("http://localhost:8080/api"),
                "headers": .object([
                    "Authorization": .string("Bearer secret"),
                    "X-Trace-ID": .string("abc123")
                ]),
                "query": .object([
                    "debug": .bool(true)
                ]),
                "body": .object([
                    "name": .string("Alice")
                ]),
                "timeout_seconds": .int(10)
            ]
        )
        let definition = ToolDefinition(
            name: NetworkToolCatalog.requestID,
            displayName: "HTTP Request",
            summary: ""
        )

        let pendingRequest = await provider.approvalRequest(for: call, definition: definition)
        let request = try XCTUnwrap(pendingRequest)
        let details = provider.details(for: call)

        XCTAssertEqual(request.toolID, NetworkToolCatalog.requestID)
        XCTAssertEqual(request.toolName, "HTTP Request")
        XCTAssertEqual(request.confirmationTitle, String(localized: "tools.approval.allow_request"))
        XCTAssertEqual(request.details, details)
        XCTAssertEqual(details.first { $0.id == "tools.approval.detail.method" }?.text, "POST")
        XCTAssertEqual(
            details.first { $0.id == "tools.approval.detail.url" }?.text,
            "http://localhost:8080/api?debug=true"
        )
        XCTAssertEqual(details.first { $0.id == "tools.approval.detail.timeout" }?.text, "10")

        let headersText = try XCTUnwrap(details.first { $0.id == "tools.approval.detail.headers" }?.text)
        XCTAssertTrue(headersText.contains(#""Authorization":"[redacted]""#))
        XCTAssertTrue(headersText.contains(#""X-Trace-ID":"abc123""#))
        XCTAssertFalse(headersText.contains("Bearer secret"))
    }

    private func makeCapturingSession(capture: NetworkRequestCapture) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkRequestCapturingURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            NetworkRequestCapturingURLProtocol.captureIDHeader: capture.id
        ]
        return URLSession(configuration: configuration)
    }

    private static func payload(from result: ToolResult) throws -> [String: Any] {
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func response(
        request: URLRequest,
        statusCode: Int,
        headers: [String: String],
        body: String
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )
        )
        let data = try XCTUnwrap(body.data(using: .utf8))
        return (response, data)
    }
}

private final class NetworkRequestCapture {
    fileprivate let id = UUID().uuidString
    private let handler: NetworkRequestCapturingURLProtocol.RequestHandler
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []

    init(handler: @escaping NetworkRequestCapturingURLProtocol.RequestHandler) {
        self.handler = handler
        NetworkRequestCapturingURLProtocol.register(capture: self, id: id)
    }

    var requests: [URLRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    func invalidate() {
        NetworkRequestCapturingURLProtocol.unregisterCapture(id: id)
    }

    fileprivate func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()

        return try handler(request)
    }
}

private final class NetworkRequestCapturingURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    fileprivate static let captureIDHeader = "X-UniLLMs-Network-Test-Capture-ID"
    private static let lock = NSLock()
    private static var capturesByID: [String: NetworkRequestCapture] = [:]

    fileprivate static func register(capture: NetworkRequestCapture, id: String) {
        lock.lock()
        capturesByID[id] = capture
        lock.unlock()
    }

    fileprivate static func unregisterCapture(id: String) {
        lock.lock()
        capturesByID[id] = nil
        lock.unlock()
    }

    private static func capture(for id: String) -> NetworkRequestCapture? {
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
