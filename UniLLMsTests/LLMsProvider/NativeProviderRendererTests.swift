//
//  NativeProviderRendererTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class NativeProviderRendererTests: XCTestCase {
    func testOpenAIRendererCanUseDeveloperInstructionRole() throws {
        let prompt = makePrompt(
            title: "Developer",
            content: "Answer tersely."
        )

        let messages = try OpenAIChatPromptRenderer.messages(
            for: ChatRequest(
                modelID: "gpt-5.4",
                messages: [makeTestChatMessage(role: .user, content: "Hello")],
                context: ChatContext(systemPrompt: prompt)
            ),
            instructionRole: .developer
        )

        XCTAssertEqual(messages.map(\.role), [.developer, .user])
        XCTAssertEqual(messages.first?.content, .text("Answer tersely."))
    }

    func testOpenAIRendererThrowsWhenImageAttachmentDataIsMissing() {
        let attachment = ChatAttachment(
            kind: .image,
            filename: "missing.png",
            contentType: "image/png",
            relativePath: ""
        )

        XCTAssertThrowsError(
            try OpenAIChatPromptRenderer.messages(
                for: ChatRequest(
                    modelID: "gpt-5.4",
                    messages: [
                        makeTestChatMessage(
                            role: .user,
                            content: "Describe this image.",
                            attachments: [attachment]
                        )
                    ],
                    context: ChatContext()
                )
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Unable to load attachment data for missing.png.")
        }
    }

    func testOpenAICompatibleRendererThrowsWhenImageAttachmentDataIsMissing() {
        let attachment = ChatAttachment(
            kind: .image,
            filename: "missing.png",
            contentType: "image/png",
            relativePath: ""
        )

        XCTAssertThrowsError(
            try OpenAICompatibleChatPromptRenderer.messages(
                for: ChatRequest(
                    modelID: "local-model",
                    messages: [
                        makeTestChatMessage(
                            role: .user,
                            content: "Describe this image.",
                            attachments: [attachment]
                        )
                    ],
                    context: ChatContext()
                )
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Unable to load attachment data for missing.png.")
        }
    }

    func testOpenRouterRendererThrowsWhenImageAttachmentDataIsMissing() {
        let attachment = ChatAttachment(
            kind: .image,
            filename: "missing.png",
            contentType: "image/png",
            relativePath: ""
        )

        XCTAssertThrowsError(
            try OpenRouterChatPromptRenderer.messages(
                for: ChatRequest(
                    modelID: "openai/gpt-5.4",
                    messages: [
                        makeTestChatMessage(
                            role: .user,
                            content: "Describe this image.",
                            attachments: [attachment]
                        )
                    ],
                    context: ChatContext()
                ),
                supportsFileAttachments: true
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Unable to load attachment data for missing.png.")
        }
    }

    func testAnthropicRendererKeepsToolsAsContentBlocks() throws {
        let prompt = makePrompt(
            title: "Tools",
            content: "Use tools when useful."
        )
        let toolCall = ChatToolCall(
            id: "toolu_1",
            toolID: "get_weather",
            arguments: ["location": .string("San Francisco")]
        )

        let renderedPrompt = try AnthropicChatPromptRenderer.render(
            request: ChatRequest(
                modelID: "claude-sonnet-4-5",
                messages: [
                    makeTestChatMessage(role: .user, content: "Weather?"),
                    makeTestChatMessage(role: .assistant, content: "", toolCalls: [toolCall]),
                    makeTestChatMessage(
                        role: .tool,
                        content: "Sunny",
                        toolCallID: "toolu_1",
                        toolDisplayName: "Weather",
                        toolStatus: .success
                    )
                ],
                context: ChatContext(systemPrompt: prompt)
            )
        )

        XCTAssertEqual(renderedPrompt.system, "Use tools when useful.")
        XCTAssertEqual(renderedPrompt.messages.map(\.role), [.user, .assistant, .user])

        let assistantPayload = try encodedJSONObject(renderedPrompt.messages[1])
        let assistantBlocks = try XCTUnwrap(assistantPayload["content"] as? [[String: Any]])
        XCTAssertEqual(assistantBlocks.first?["type"] as? String, "tool_use")
        XCTAssertEqual(assistantBlocks.first?["id"] as? String, "toolu_1")
        XCTAssertEqual(assistantBlocks.first?["name"] as? String, "get_weather")

        let toolPayload = try encodedJSONObject(renderedPrompt.messages[2])
        let toolBlocks = try XCTUnwrap(toolPayload["content"] as? [[String: Any]])
        XCTAssertEqual(toolBlocks.first?["type"] as? String, "tool_result")
        XCTAssertEqual(toolBlocks.first?["tool_use_id"] as? String, "toolu_1")
        XCTAssertEqual(toolBlocks.first?["content"] as? String, "Sunny")
    }

    func testAnthropicStreamParserAccumulatesToolUseBlocks() throws {
        var accumulator = AnthropicToolCallAccumulator()

        let textDelta = try XCTUnwrap(
            AnthropicAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Checking"}}"#,
                accumulator: &accumulator,
                serviceName: "Anthropic"
            )
        )
        XCTAssertEqual(textDelta.content, "Checking")

        XCTAssertNil(
            try AnthropicAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_weather","input":{}}}"#,
                accumulator: &accumulator,
                serviceName: "Anthropic"
            )
        )
        XCTAssertNil(
            try AnthropicAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"location\":\"SF\"}"}}"#,
                accumulator: &accumulator,
                serviceName: "Anthropic"
            )
        )

        let toolCall = try XCTUnwrap(accumulator.completedToolCalls().first)
        XCTAssertEqual(toolCall.id, "toolu_1")
        XCTAssertEqual(toolCall.toolID, "get_weather")
        XCTAssertEqual(toolCall.argumentObject, ["location": .string("SF")])
    }

    func testGeminiRendererKeepsToolsAsFunctionParts() throws {
        let prompt = makePrompt(
            title: "Tools",
            content: "Use tools when useful."
        )
        let toolCall = ChatToolCall(
            id: "gemini_tool_call_0",
            toolID: "get_weather",
            arguments: ["location": .string("San Francisco")]
        )

        let renderedPrompt = try GeminiChatPromptRenderer.render(
            request: ChatRequest(
                modelID: "gemini-2.5-flash",
                messages: [
                    makeTestChatMessage(role: .user, content: "Weather?"),
                    makeTestChatMessage(role: .assistant, content: "", toolCalls: [toolCall]),
                    makeTestChatMessage(
                        role: .tool,
                        content: "Sunny",
                        toolCallID: "gemini_tool_call_0",
                        toolDisplayName: "Weather",
                        toolStatus: .success
                    )
                ],
                context: ChatContext(systemPrompt: prompt)
            )
        )

        XCTAssertEqual(renderedPrompt.systemInstruction?.role, nil)
        XCTAssertEqual(renderedPrompt.systemInstruction?.parts, [.text("Use tools when useful.")])
        XCTAssertEqual(renderedPrompt.contents.map(\.role), ["user", "model", "user"])

        let assistantPayload = try encodedJSONObject(renderedPrompt.contents[1])
        let assistantParts = try XCTUnwrap(assistantPayload["parts"] as? [[String: Any]])
        let functionCall = try XCTUnwrap(assistantParts.first?["functionCall"] as? [String: Any])
        XCTAssertEqual(functionCall["name"] as? String, "get_weather")
        XCTAssertNil(assistantParts.first?["thoughtSignature"])

        let toolPayload = try encodedJSONObject(renderedPrompt.contents[2])
        let toolParts = try XCTUnwrap(toolPayload["parts"] as? [[String: Any]])
        let functionResponse = try XCTUnwrap(toolParts.first?["functionResponse"] as? [String: Any])
        XCTAssertEqual(functionResponse["name"] as? String, "get_weather")
        XCTAssertEqual(functionResponse["id"] as? String, "gemini_tool_call_0")
        XCTAssertEqual(
            (functionResponse["response"] as? [String: Any])?["result"] as? String,
            "Sunny"
        )
    }

    func testGeminiRendererPreservesFunctionCallThoughtSignature() throws {
        let toolCall = ChatToolCall(
            id: "call_abc",
            toolID: "get_weather",
            arguments: ["location": .string("SF")],
            providerMetadata: [
                GeminiProviderError.thoughtSignatureMetadataKey: .string("signature_abc")
            ]
        )

        let renderedPrompt = try GeminiChatPromptRenderer.render(
            request: ChatRequest(
                modelID: "gemini-3-pro-preview",
                messages: [
                    makeTestChatMessage(role: .assistant, content: "", toolCalls: [toolCall])
                ],
                context: ChatContext()
            )
        )

        let assistantPayload = try encodedJSONObject(renderedPrompt.contents[0])
        let assistantParts = try XCTUnwrap(assistantPayload["parts"] as? [[String: Any]])
        XCTAssertEqual(assistantParts.first?["thoughtSignature"] as? String, "signature_abc")
    }

    func testGeminiRendererUsesErrorKeyForFailedFunctionResponses() throws {
        let renderedPrompt = try GeminiChatPromptRenderer.render(
            request: ChatRequest(
                modelID: "gemini-2.5-flash",
                messages: [
                    makeTestChatMessage(
                        role: .tool,
                        content: "Invalid tool input.",
                        toolCallID: "call_abc",
                        toolDisplayName: "get_weather",
                        toolStatus: .error
                    )
                ],
                context: ChatContext()
            )
        )

        let payload = try encodedJSONObject(renderedPrompt.contents[0])
        let parts = try XCTUnwrap(payload["parts"] as? [[String: Any]])
        let functionResponse = try XCTUnwrap(parts.first?["functionResponse"] as? [String: Any])
        let response = try XCTUnwrap(functionResponse["response"] as? [String: Any])
        XCTAssertEqual(response["error"] as? String, "Invalid tool input.")
    }

    func testGeminiStreamParserDecodesTextAndFunctionCallParts() throws {
        var toolCallIndex = 0
        let textDelta = try XCTUnwrap(
            GeminiAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#,
                toolCallIndex: &toolCallIndex,
                serviceName: "Gemini"
            )
        )
        XCTAssertEqual(textDelta.content, "Hello")

        let toolDelta = try XCTUnwrap(
            GeminiAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"candidates":[{"content":{"parts":[{"functionCall":{"id":"call_abc","name":"get_weather","args":{"location":"SF"}},"thoughtSignature":"signature_abc"}]}}]}"#,
                toolCallIndex: &toolCallIndex,
                serviceName: "Gemini"
            )
        )

        let toolCall = try XCTUnwrap(toolDelta.toolCalls.first)
        XCTAssertEqual(toolCall.id, "call_abc")
        XCTAssertEqual(toolCall.toolID, "get_weather")
        XCTAssertEqual(toolCall.argumentObject, ["location": .string("SF")])
        XCTAssertEqual(
            toolCall.providerMetadata[GeminiProviderError.thoughtSignatureMetadataKey],
            .string("signature_abc")
        )
        XCTAssertEqual(toolCallIndex, 1)
    }

    func testGeminiStreamParserThrowsWhenPromptIsBlocked() throws {
        var toolCallIndex = 0

        XCTAssertThrowsError(
            try GeminiAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"promptFeedback":{"blockReason":"SAFETY","blockReasonMessage":"Blocked by safety policy."}}"#,
                toolCallIndex: &toolCallIndex,
                serviceName: "Gemini"
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Blocked by safety policy.")
        }
    }

    func testGeminiStreamParserThrowsWhenCandidateHasBlockedFinishReason() throws {
        var toolCallIndex = 0

        XCTAssertThrowsError(
            try GeminiAPIClient.streamDelta(
                fromServerSentEventLine: #"data: {"candidates":[{"finishReason":"MISSING_THOUGHT_SIGNATURE","finishMessage":"Missing thought signature."}]}"#,
                toolCallIndex: &toolCallIndex,
                serviceName: "Gemini"
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Missing thought signature.")
        }
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makePrompt(
        title: String,
        content: String,
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> SystemPromptRecord {
        SystemPromptRecord(
            title: title,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
