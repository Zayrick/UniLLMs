//
//  LLMsProviderStreamSupportTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class LLMsProviderStreamSupportTests: XCTestCase {
    func testChatResponseStreamMapsProviderDeltasAndFinishes() async throws {
        let source = AsyncThrowingStream<TestProviderDelta, Error> { continuation in
            continuation.yield(
                TestProviderDelta(
                    content: "Hello",
                    reasoning: "Because",
                    toolCalls: [
                        ChatToolCall(
                            id: "call_1",
                            toolID: "search",
                            serializedArguments: #"{"query":"swift"}"#
                        )
                    ]
                )
            )
            continuation.finish()
        }

        var receivedDeltas: [ChatResponseDelta] = []
        for try await delta in LLMsProviderStreamSupport.chatResponseStream(from: source) {
            receivedDeltas.append(delta)
        }

        XCTAssertEqual(receivedDeltas.count, 1)
        XCTAssertEqual(receivedDeltas.first?.content, "Hello")
        XCTAssertEqual(receivedDeltas.first?.reasoning, "Because")
        XCTAssertEqual(receivedDeltas.first?.toolCalls.first?.toolID, "search")
    }

    func testChatResponseStreamPropagatesProviderErrors() async {
        let source = AsyncThrowingStream<TestProviderDelta, Error> { continuation in
            continuation.finish(throwing: StreamSupportTestError.failed)
        }

        do {
            for try await _ in LLMsProviderStreamSupport.chatResponseStream(from: source, transform: Self.chatDelta) {}
            XCTFail("Expected provider stream error to be propagated.")
        } catch StreamSupportTestError.failed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFailedChatResponseStreamFinishesThrowingProvidedError() async {
        do {
            for try await _ in LLMsProviderStreamSupport.failedChatResponseStream(StreamSupportTestError.failed) {}
            XCTFail("Expected failed stream to throw.")
        } catch StreamSupportTestError.failed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testContainsFileAttachmentsOnlyMatchesFileAttachments() {
        let imageRequest = ChatRequest(
            modelID: "model",
            messages: [
                makeTestChatMessage(
                    role: .user,
                    content: "Image",
                    attachments: [
                        ChatAttachment(
                            kind: .image,
                            filename: "image.png",
                            contentType: "image/png",
                            relativePath: "image.png"
                        )
                    ]
                )
            ],
            context: ChatContext()
        )
        let fileRequest = ChatRequest(
            modelID: "model",
            messages: [
                makeTestChatMessage(
                    role: .user,
                    content: "File",
                    attachments: [
                        ChatAttachment(
                            kind: .file,
                            filename: "document.pdf",
                            contentType: "application/pdf",
                            relativePath: "document.pdf"
                        )
                    ]
                )
            ],
            context: ChatContext()
        )

        XCTAssertFalse(LLMsProviderStreamSupport.containsFileAttachments(imageRequest))
        XCTAssertTrue(LLMsProviderStreamSupport.containsFileAttachments(fileRequest))
    }

    nonisolated private static func chatDelta(_ delta: TestProviderDelta) -> ChatResponseDelta {
        delta.chatResponseDelta
    }
}

nonisolated private struct TestProviderDelta: LLMsProviderStreamSupport.ChatResponseDeltaConvertible {
    var content: String
    var reasoning: String
    var toolCalls: [ChatToolCall]

    var chatResponseDelta: ChatResponseDelta {
        ChatResponseDelta(
            content: content,
            reasoning: reasoning,
            toolCalls: toolCalls
        )
    }
}

private enum StreamSupportTestError: Error {
    case failed
}
