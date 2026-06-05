//
//  ChatToolLoopContinuationPlan.swift
//  UniLLMs
//
//  Describes the assistant message and started tool events for one tool-loop continuation.
//

import Foundation

nonisolated struct ChatToolLoopContinuationPlan: Equatable {
    var assistantMessage: ChatMessage
    var toolCalls: [ChatToolCall]
    var startedEvents: [ChatTurnEvent]

    init(
        content: String,
        reasoning: String,
        toolCalls: [ChatToolCall],
        createdAt: Date
    ) {
        self.toolCalls = toolCalls
        assistantMessage = ChatMessage(
            role: .assistant,
            content: content,
            reasoning: reasoning,
            toolCalls: toolCalls,
            createdAt: createdAt
        )
        startedEvents = toolCalls.isEmpty ? [] : [.timelineEvent(.assistantToolCalls(toolCalls))]
        startedEvents.append(
            contentsOf: toolCalls.map { toolCall in
                .displayDelta(
                    ChatResponseDelta(
                        displayParts: [.toolEvent(.started(toolCall))]
                    )
                )
            }
        )
    }
}
