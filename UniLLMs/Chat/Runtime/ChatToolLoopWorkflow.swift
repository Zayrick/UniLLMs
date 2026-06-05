//
//  ChatToolLoopWorkflow.swift
//  UniLLMs
//
//  Owns provider tool-loop continuation state for a chat turn.
//

import Foundation

final class ChatToolLoopWorkflow {
    struct State: Equatable {
        var requestMessages: [ChatMessage]
        private(set) var completedToolIterations: Int

        init(
            requestMessages: [ChatMessage],
            completedToolIterations: Int = 0
        ) {
            self.requestMessages = requestMessages
            self.completedToolIterations = completedToolIterations
        }

        fileprivate mutating func recordCompletedToolIteration() {
            completedToolIterations += 1
        }
    }

    enum Decision: Equatable {
        case finish
        case `continue`(State)
    }

    private let toolCallExecutor: ChatToolCallExecutor
    private let maximumToolIterations: Int
    private let clock: any AppClock

    init(
        toolManager: ToolManager,
        maximumToolIterations: Int = 8,
        clock: any AppClock = SystemAppClock()
    ) {
        toolCallExecutor = ChatToolCallExecutor(toolManager: toolManager, clock: clock)
        self.maximumToolIterations = max(0, maximumToolIterations)
        self.clock = clock
    }

    func decision(
        after assistantResponse: ChatAssistantResponseSnapshot,
        state: State,
        context: ChatContext,
        emit: (ChatTurnEvent) -> Void
    ) async throws -> Decision {
        guard !context.availableTools.isEmpty,
              !assistantResponse.toolCalls.isEmpty else {
            return .finish
        }

        guard state.completedToolIterations < maximumToolIterations else {
            throw ToolExecutionLoopError.exceededMaximumIterations(maximumToolIterations)
        }

        var nextState = state
        nextState.recordCompletedToolIteration()

        let continuationPlan = ChatToolLoopContinuationPlan(
            content: assistantResponse.content,
            reasoning: assistantResponse.reasoning,
            toolCalls: assistantResponse.toolCalls,
            createdAt: clock.now
        )
        nextState.requestMessages.append(continuationPlan.assistantMessage)
        continuationPlan.startedEvents.forEach(emit)

        let toolMessages = await toolCallExecutor.execute(
            continuationPlan.toolCalls,
            context: context,
            emit: emit
        )
        nextState.requestMessages.append(contentsOf: toolMessages)
        return .continue(nextState)
    }
}
