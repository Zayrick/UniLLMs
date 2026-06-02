//
//  FakeLLMsProviderTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class FakeLLMsProviderTests: XCTestCase {
    @MainActor
    func testFakeStaticModelReturnsSingleDelayedResponse() async throws {
        let provider = FakeLLMsProvider(staticResponseDelayNanoseconds: 0)
        var deltas: [ChatResponseDelta] = []

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.staticResponse,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            deltas.append(delta)
        }

        XCTAssertEqual(deltas.count, 1)
        XCTAssertTrue(deltas[0].content.contains("fake static response"))
    }

    @MainActor
    func testFakeStreamModelYieldsResponseOneCharacterAtATime() async throws {
        let provider = FakeLLMsProvider(
            streamInitialDelayNanoseconds: 0,
            streamCharacterDelayNanoseconds: 0
        )
        var streamedContent = ""

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.stream,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            XCTAssertLessThanOrEqual(delta.content.count, 1)
            streamedContent += delta.content
        }

        XCTAssertTrue(streamedContent.contains("fake streaming response"))
    }

    @MainActor
    func testFakeMarkdownStaticModelReturnsSingleMarkdownFixture() async throws {
        let provider = FakeLLMsProvider(staticResponseDelayNanoseconds: 0)
        var deltas: [ChatResponseDelta] = []

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.markdownStatic,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            deltas.append(delta)
        }

        XCTAssertEqual(deltas.count, 1)
        XCTAssertTrue(deltas[0].content.contains("# UniLLMs Markdown Torture Fixture"))
        XCTAssertTrue(deltas[0].content.contains("> [!NOTE]"))
        XCTAssertTrue(deltas[0].content.contains("```swift"))
        XCTAssertTrue(deltas[0].content.contains("$$"))
    }

    @MainActor
    func testFakeMarkdownStreamModelYieldsMarkdownFixtureInRandomSizedCharacterChunks() async throws {
        let provider = FakeLLMsProvider(
            streamInitialDelayNanoseconds: 0,
            markdownStreamChunkDelayRangeNanoseconds: 0...0
        )
        var deltas: [ChatResponseDelta] = []
        var streamedContent = ""

        for try await delta in provider.streamChat(
            request: ChatRequest(
                modelID: FakeLLMsProvider.ModelID.markdownStream,
                messages: [],
                context: ChatContext()
            ),
            configuration: LLMsProviderConfiguration()
        ) {
            deltas.append(delta)
            XCTAssertGreaterThanOrEqual(delta.content.count, 1)
            XCTAssertLessThanOrEqual(delta.content.count, 6)
            streamedContent += delta.content
        }

        XCTAssertGreaterThan(deltas.count, 10)
        XCTAssertTrue(streamedContent.contains("# UniLLMs Markdown Torture Fixture"))
        XCTAssertTrue(streamedContent.contains("| Feature | Syntax | Expected Alignment | Notes |"))
        XCTAssertTrue(streamedContent.contains("```mermaid"))
        XCTAssertTrue(streamedContent.contains("\\begin{bmatrix}"))
    }
}
