//
//  ChatTurnRunner.swift
//  UniLLMs
//
//  Runs a single chat turn by connecting prompt assembly to streaming response output.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class ChatTurnRunner {
    private let providerManager: LLMsProviderManager
    private let toolLoopWorkflow: ChatToolLoopWorkflow

    init(
        providerManager: LLMsProviderManager,
        toolManager: ToolManager,
        maximumToolIterations: Int = 8,
        clock: any AppClock = SystemAppClock()
    ) {
        self.providerManager = providerManager
        toolLoopWorkflow = ChatToolLoopWorkflow(
            toolManager: toolManager,
            maximumToolIterations: maximumToolIterations,
            clock: clock
        )
    }

    func streamResponse(
        provider: LLMsProviderRecord,
        modelID: String,
        context: ChatContext
    ) -> AsyncThrowingStream<ChatTurnEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var toolLoopState = ChatToolLoopWorkflow.State(
                        requestMessages: context.messages
                    )

                    while true {
                        try Task.checkCancellation()
                        let assistantResponse = try await streamSingleResponse(
                            provider: provider,
                            modelID: modelID,
                            messages: toolLoopState.requestMessages,
                            context: context,
                            into: continuation
                        )

                        let toolLoopDecision = try await toolLoopWorkflow.decision(
                            after: assistantResponse,
                            state: toolLoopState,
                            context: context,
                            emit: { continuation.yield($0) }
                        )
                        switch toolLoopDecision {
                        case .finish:
                            continuation.finish()
                            return
                        case let .continue(nextState):
                            toolLoopState = nextState
                        }
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
        into continuation: AsyncThrowingStream<ChatTurnEvent, Error>.Continuation
    ) async throws -> ChatAssistantResponseSnapshot {
        let stream = try providerManager.streamChat(
            provider: provider,
            modelID: modelID,
            messages: messages,
            context: context
        )
        var accumulator = ChatAssistantResponseAccumulator()

        for try await delta in stream {
            try Task.checkCancellation()
            if let visibleDelta = accumulator.append(delta: delta, context: context) {
                continuation.yield(.displayDelta(visibleDelta))
            }
        }

        return accumulator.snapshot
    }
}
