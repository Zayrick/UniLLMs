//
//  MCPHTTPClientTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class MCPHTTPClientTests: XCTestCase {
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
