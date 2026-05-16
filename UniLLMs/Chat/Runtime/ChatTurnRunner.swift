//
//  ChatTurnRunner.swift
//  UniLLMs
//
//  Runs a single chat turn by connecting prompt assembly to streaming response output.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class ChatTurnRunner {
    private enum ToolLoop {
        static let maximumRounds = 4
    }

    private struct SingleAssistantResponse {
        var content = ""
        var reasoning = ""
        var toolCalls: [ChatToolCall] = []
    }

    private let responseStreamer: ChatResponseStreamer
    private let promptAssembler: ChatPromptAssembler
    private let toolManager: ToolManager

    init(
        responseStreamer: ChatResponseStreamer,
        promptAssembler: ChatPromptAssembler = ChatPromptAssembler(),
        toolManager: ToolManager
    ) {
        self.responseStreamer = responseStreamer
        self.promptAssembler = promptAssembler
        self.toolManager = toolManager
    }

    func streamResponse(
        provider: LLMsProviderRecord,
        modelID: String,
        context: ChatContext
    ) -> AsyncThrowingStream<ChatTurnEvent, Error> {
        let initialMessages = promptAssembler.assembleMessages(from: context)
        let allowsTools = !context.availableTools.isEmpty
        let maxRounds = allowsTools ? ToolLoop.maximumRounds : 0

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var requestMessages = initialMessages

                    for round in 0...maxRounds {
                        let assistantResponse = try await streamSingleResponse(
                            provider: provider,
                            modelID: modelID,
                            messages: requestMessages,
                            context: context,
                            into: continuation
                        )

                        if !allowsTools || assistantResponse.toolCalls.isEmpty {
                            continuation.finish()
                            return
                        }

                        guard round < maxRounds else {
                            throw ToolExecutionLoopError.maximumRoundsExceeded
                        }

                        let assistantMessage = ChatMessage(
                            role: .assistant,
                            content: assistantResponse.content,
                            reasoning: assistantResponse.reasoning,
                            toolCalls: assistantResponse.toolCalls
                        )
                        requestMessages.append(assistantMessage)

                        let toolMessages = await executeToolCalls(
                            assistantResponse.toolCalls,
                            context: context,
                            into: continuation
                        )
                        requestMessages.append(contentsOf: toolMessages)
                    }

                    continuation.finish()
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
        into continuation: AsyncThrowingStream<ChatTurnEvent, Error>.Continuation
    ) async throws -> SingleAssistantResponse {
        let stream = try responseStreamer.streamResponse(
            provider: provider,
            modelID: modelID,
            messages: messages,
            context: context
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
    ) async -> [ChatMessage] {
        var messages: [ChatMessage] = []
        let executionContext = ToolExecutionContext(session: context.session)

        for toolCall in toolCalls {
            let toolDisplayName = Self.resolvedToolDisplayName(for: toolCall, context: context)
            let startedEvent = ChatToolDisplayEvent.started(
                callID: toolCall.id,
                toolID: toolCall.toolID,
                displayName: toolDisplayName,
                arguments: toolCall.arguments
            )
            continuation.yield(
                .timelineEvent(
                    .toolCallStarted(
                        callID: toolCall.id,
                        toolID: toolCall.toolID,
                        displayName: toolDisplayName,
                        arguments: toolCall.arguments
                    )
                )
            )
            continuation.yield(
                .displayDelta(
                    ChatResponseDelta(
                        displayParts: [.toolEvent(startedEvent)]
                    )
                )
            )

            do {
                let call = ToolCall(
                    id: toolCall.id,
                    toolID: toolCall.toolID,
                    arguments: try Self.parseArguments(toolCall.arguments)
                )
                let result = try await toolManager.execute(call: call, context: executionContext)
                let completedEvent = ChatToolDisplayEvent.completed(
                    callID: toolCall.id,
                    toolID: toolCall.toolID,
                    displayName: toolDisplayName,
                    result: result.content
                )
                continuation.yield(
                    .timelineEvent(
                        .toolCallCompleted(
                            callID: toolCall.id,
                            toolID: toolCall.toolID,
                            displayName: toolDisplayName,
                            result: result.content
                        )
                    )
                )
                continuation.yield(
                    .displayDelta(
                        ChatResponseDelta(
                            displayParts: [.toolEvent(completedEvent)]
                        )
                    )
                )
                messages.append(
                    ChatMessage(
                        role: .tool,
                        content: result.content,
                        toolCallID: result.callID,
                        toolDisplayName: toolDisplayName
                    )
                )
            } catch {
                let failedEvent = ChatToolDisplayEvent.failed(
                    callID: toolCall.id,
                    toolID: toolCall.toolID,
                    displayName: toolDisplayName,
                    message: error.localizedDescription
                )
                continuation.yield(
                    .timelineEvent(
                        .toolCallFailed(
                            callID: toolCall.id,
                            toolID: toolCall.toolID,
                            displayName: toolDisplayName,
                            message: error.localizedDescription
                        )
                    )
                )
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
                        content: "Tool execution failed: \(error.localizedDescription)",
                        toolCallID: toolCall.id,
                        toolDisplayName: toolDisplayName
                    )
                )
            }
        }

        return messages
    }

    private static func parseArguments(_ arguments: String) throws -> [String: JSONValue] {
        let trimmedArguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArguments.isEmpty else {
            return [:]
        }

        guard let data = trimmedArguments.data(using: .utf8),
              let arguments = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw ToolExecutionLoopError.invalidArguments
        }

        return arguments
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
            displayName: toolDisplayName(for: toolCall.toolID, context: context)
        )
    }

    private static func resolvedToolDisplayName(for toolCall: ChatToolCall, context: ChatContext) -> String {
        let storedDisplayName = toolCall.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return storedDisplayName.isEmpty ? toolDisplayName(for: toolCall.toolID, context: context) : storedDisplayName
    }
}

enum ToolExecutionLoopError: LocalizedError, Equatable {
    case invalidArguments
    case maximumRoundsExceeded

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "The model produced invalid tool arguments."
        case .maximumRoundsExceeded:
            return "Tool calling did not finish after the maximum number of rounds."
        }
    }
}
