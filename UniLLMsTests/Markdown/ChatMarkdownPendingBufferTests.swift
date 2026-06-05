//
//  ChatMarkdownPendingBufferTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatMarkdownPendingBufferTests: XCTestCase {
    func testBufferIgnoresEmptyChunks() {
        var buffer = ChatMarkdownPendingBuffer()

        buffer.append("")

        XCTAssertFalse(buffer.hasPendingMarkdown)
        XCTAssertEqual(buffer.nextChunk(maxCharacters: 10), "")
        XCTAssertFalse(buffer.hasPendingMarkdown)
    }

    func testNextChunkRespectsCharacterBudgetAcrossChunks() {
        var buffer = ChatMarkdownPendingBuffer()

        buffer.append("Hello")
        buffer.append("World")

        XCTAssertEqual(buffer.nextChunk(maxCharacters: 7), "HelloWo")
        XCTAssertTrue(buffer.hasPendingMarkdown)
        XCTAssertEqual(buffer.nextChunk(maxCharacters: 7), "rld")
        XCTAssertFalse(buffer.hasPendingMarkdown)
    }

    func testDrainReturnsRemainingMarkdownAfterPartialFlush() {
        var buffer = ChatMarkdownPendingBuffer()

        buffer.append("abcdef")
        buffer.append("gh")

        XCTAssertEqual(buffer.nextChunk(maxCharacters: 2), "ab")
        XCTAssertEqual(buffer.drain(), "cdefgh")
        XCTAssertFalse(buffer.hasPendingMarkdown)
    }

    func testClearDropsPartiallyConsumedChunks() {
        var buffer = ChatMarkdownPendingBuffer()

        buffer.append("abcdef")
        XCTAssertEqual(buffer.nextChunk(maxCharacters: 3), "abc")

        buffer.clear()

        XCTAssertFalse(buffer.hasPendingMarkdown)
        XCTAssertEqual(buffer.drain(), "")
    }

    func testCompactionKeepsRemainingChunksAfterManyConsumedChunks() {
        var buffer = ChatMarkdownPendingBuffer()
        for _ in 0..<70 {
            buffer.append("x")
        }

        XCTAssertEqual(buffer.nextChunk(maxCharacters: 65), String(repeating: "x", count: 65))
        XCTAssertTrue(buffer.hasPendingMarkdown)
        XCTAssertEqual(buffer.drain(), String(repeating: "x", count: 5))
        XCTAssertFalse(buffer.hasPendingMarkdown)
    }
}
