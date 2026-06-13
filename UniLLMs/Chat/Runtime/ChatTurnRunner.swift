//
//  ChatTurnRunner.swift
//  UniLLMs
//
//  Runs a single chat turn by connecting prompt assembly to streaming response output.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class ChatTurnRunner {
    private struct SingleAssistantResponse {
        var content = ""
        var reasoning = ""
        var toolCalls: [ChatToolCall] = []
    }

    private let responseStreamer: ChatResponseStreamer
    private let toolManager: ToolManager

    init(
        responseStreamer: ChatResponseStreamer,
        toolManager: ToolManager
    ) {
        self.responseStreamer = responseStreamer
        self.toolManager = toolManager
    }

    func streamResponse(
        provider: LLMsProviderRecord,
        modelID: String,
        context: ChatContext,
        reasoningEffort: String? = nil
    ) -> AsyncThrowingStream<ChatTurnEvent, Error> {
        let allowsTools = !context.availableTools.isEmpty

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var requestMessages = context.messages

                    while true {
                        try Task.checkCancellation()
                        let assistantResponse = try await streamSingleResponse(
                            provider: provider,
                            modelID: modelID,
                            messages: requestMessages,
                            context: context,
                            reasoningEffort: reasoningEffort,
                            into: continuation
                        )

                        if !allowsTools || assistantResponse.toolCalls.isEmpty {
                            continuation.finish()
                            return
                        }

                        let assistantMessage = ChatMessage(
                            role: .assistant,
                            content: assistantResponse.content,
                            reasoning: assistantResponse.reasoning,
                            toolCalls: assistantResponse.toolCalls
                        )
                        requestMessages.append(assistantMessage)
                        continuation.yield(.timelineEvent(.assistantToolCalls(assistantResponse.toolCalls)))
                        for toolCall in assistantResponse.toolCalls {
                            continuation.yield(
                                .displayDelta(
                                    ChatResponseDelta(
                                        displayParts: [.toolEvent(.started(toolCall))]
                                    )
                                )
                            )
                        }

                        let toolMessages = try await executeToolCalls(
                            assistantResponse.toolCalls,
                            context: context,
                            into: continuation
                        )
                        requestMessages.append(contentsOf: toolMessages)
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamSingleResponse(
        provider: LLMsProviderRecord,
        modelID: String,
        messages: [ChatMessage],
        context: ChatContext,
        reasoningEffort: String?,
        into continuation: AsyncThrowingStream<ChatTurnEvent, Error>.Continuation
    ) async throws -> SingleAssistantResponse {
        let stream = try responseStreamer.streamResponse(
            provider: provider,
            modelID: modelID,
            messages: messages,
            context: context,
            reasoningEffort: reasoningEffort
        )
        var assistantResponse = SingleAssistantResponse()

        for try await delta in stream {
            try Task.checkCancellation()
            if !delta.toolCalls.isEmpty {
                assistantResponse.toolCalls.append(
                    contentsOf: delta.toolCalls.map { toolCall in
                        Self.toolCallWithDisplayName(toolCall, context: context)
                    }
                )
            }

            let visibleDelta = ChatResponseDelta(
                content: delta.content,
                reasoning: delta.reasoning,
                displayParts: delta.displayParts
            )
            if !visibleDelta.isEmpty {
                assistantResponse.content += visibleDelta.content
                assistantResponse.reasoning += visibleDelta.reasoning
                continuation.yield(.displayDelta(visibleDelta))
            }
        }

        return assistantResponse
    }

    private func executeToolCalls(
        _ toolCalls: [ChatToolCall],
        context: ChatContext,
        into continuation: AsyncThrowingStream<ChatTurnEvent, Error>.Continuation
    ) async throws -> [ChatMessage] {
        var messages: [ChatMessage] = []
        let executionContext = ToolExecutionContext(session: context.session)

        for toolCall in toolCalls {
            try Task.checkCancellation()

            let toolDisplayName = Self.resolvedToolDisplayName(for: toolCall, context: context)
            let displayToolCall = ChatToolCall(
                id: toolCall.id,
                toolID: toolCall.toolID,
                arguments: toolCall.arguments,
                displayName: toolDisplayName,
                providerMetadata: toolCall.providerMetadata
            )

            do {
                let call = ToolCall(
                    id: toolCall.id,
                    toolID: toolCall.toolID,
                    arguments: try Self.parseArguments(toolCall.arguments)
                )
                let result = try await toolManager.execute(call: call, context: executionContext)
                let event = Self.toolEvent(for: displayToolCall, result: result)
                continuation.yield(.timelineEvent(.toolEvent(event)))
                continuation.yield(
                    .displayDelta(
                        ChatResponseDelta(
                            displayParts: [.toolEvent(event)]
                        )
                    )
                )
                messages.append(
                    ChatMessage(
                        role: .tool,
                        content: event.providerMessageContent,
                        toolCallID: toolCall.id,
                        toolDisplayName: toolDisplayName,
                        toolStatus: result.status
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let failedEvent = ChatToolEvent.failed(displayToolCall, message: error.localizedDescription)
                continuation.yield(.timelineEvent(.toolEvent(failedEvent)))
                continuation.yield(
                    .displayDelta(
                        ChatResponseDelta(
                            displayParts: [.toolEvent(failedEvent)]
                        )
                    )
                )
                messages.append(
                    ChatMessage(
                        role: .tool,
                        content: failedEvent.providerMessageContent,
                        toolCallID: toolCall.id,
                        toolDisplayName: toolDisplayName,
                        toolStatus: .error
                    )
                )
            }
        }

        return messages
    }

    private static func parseArguments(_ arguments: JSONValue) throws -> [String: JSONValue] {
        guard let arguments = arguments.objectValue else {
            throw ToolExecutionLoopError.invalidArguments
        }

        return arguments
    }

    private static func toolEvent(for toolCall: ChatToolCall, result: ToolResult) -> ChatToolEvent {
        if result.isError {
            return .failed(toolCall, message: result.content)
        }

        return .completed(toolCall, result: result.content)
    }

    private static func toolDisplayName(for toolID: String, context: ChatContext) -> String {
        guard let definition = context.availableTools.first(where: { $0.id == toolID }) else {
            return toolID
        }

        return definition.presentationName
    }

    private static func toolCallWithDisplayName(_ toolCall: ChatToolCall, context: ChatContext) -> ChatToolCall {
        ChatToolCall(
            id: toolCall.id,
            toolID: toolCall.toolID,
            arguments: toolCall.arguments,
            displayName: toolDisplayName(for: toolCall.toolID, context: context),
            providerMetadata: toolCall.providerMetadata
        )
    }

    private static func resolvedToolDisplayName(for toolCall: ChatToolCall, context: ChatContext) -> String {
        let storedDisplayName = toolCall.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return storedDisplayName.isEmpty ? toolDisplayName(for: toolCall.toolID, context: context) : storedDisplayName
    }
}

enum ToolExecutionLoopError: LocalizedError, Equatable {
    case invalidArguments

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return String(localized: .runtimeErrorInvalidToolArguments)
        }
    }
}
