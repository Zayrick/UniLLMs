//
//  MCPHTTPClientTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class MCPHTTPClientTests: XCTestCase {
    func testJSONRPCResponseDecoderDecodesApplicationJSONResult() throws {
        let data = try XCTUnwrap(
            #"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#.data(using: .utf8)
        )

        let response = try MCPJSONRPCResponseDecoder.decode(
            data: data,
            contentType: "application/json; charset=utf-8",
            serverName: "Test MCP"
        )

        XCTAssertEqual(response.id, .int(1))
        XCTAssertEqual(response.result, .object(["tools": .array([])]))
        XCTAssertNil(response.error)
    }

    func testJSONRPCResponseDecoderDecodesApplicationJSONError() throws {
        let data = try XCTUnwrap(
            #"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Missing method"}}"#
                .data(using: .utf8)
        )

        let response = try MCPJSONRPCResponseDecoder.decode(
            data: data,
            contentType: "application/json",
            serverName: "Test MCP"
        )

        XCTAssertEqual(response.error?.code, -32601)
        XCTAssertEqual(response.error?.message, "Missing method")
        XCTAssertNil(response.result)
    }

    func testJSONRPCResponseDecoderRejectsApplicationJSONWithoutRequestResponse() throws {
        let data = try XCTUnwrap(
            #"{"jsonrpc":"2.0","method":"notifications/progress","params":{}}"#.data(using: .utf8)
        )

        XCTAssertThrowsError(
            try MCPJSONRPCResponseDecoder.decode(
                data: data,
                contentType: "application/json",
                serverName: "Test MCP"
            )
        ) { error in
            XCTAssertEqual(error as? MCPHTTPClientError, .invalidResponse("Test MCP"))
        }
    }

    func testJSONRPCResponseDecoderReturnsFirstSSERequestResponse() throws {
        let body = """
        : keep-alive
        data: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}
        data: {"jsonrpc":"2.0","id":2,"result":{"content":[]}}

        """
        let data = try XCTUnwrap(body.data(using: .utf8))

        let response = try MCPJSONRPCResponseDecoder.decode(
            data: data,
            contentType: "text/event-stream",
            serverName: "Test MCP"
        )

        XCTAssertEqual(response.id, .int(2))
        XCTAssertEqual(response.result, .object(["content": .array([])]))
    }

    func testJSONRPCResponseDecoderThrowsInvalidResponseWhenSSEHasNoRequestResponse() throws {
        let data = try XCTUnwrap(
            #"data: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}"#.data(using: .utf8)
        )

        XCTAssertThrowsError(
            try MCPJSONRPCResponseDecoder.decode(
                data: data,
                contentType: "text/event-stream",
                serverName: "Test MCP"
            )
        ) { error in
            XCTAssertEqual(error as? MCPHTTPClientError, .invalidResponse("Test MCP"))
        }
    }

    func testJSONRPCResponseDecoderThrowsInvalidResponseForMalformedSSEData() throws {
        let data = try XCTUnwrap(
            """
            : keep-alive
            data: {
            data: {"jsonrpc":"2.0","id":2,"result":{}}
            """.data(using: .utf8)
        )

        XCTAssertThrowsError(
            try MCPJSONRPCResponseDecoder.decode(
                data: data,
                contentType: "text/event-stream",
                serverName: "Test MCP"
            )
        ) { error in
            XCTAssertEqual(error as? MCPHTTPClientError, .invalidResponse("Test MCP"))
        }
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
}
