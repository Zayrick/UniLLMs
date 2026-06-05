//
//  ChatAssistantResponseAccumulator.swift
//  UniLLMs
//
//  Accumulates one assistant response while producing visible streaming deltas.
//

import Foundation

nonisolated struct ChatAssistantResponseSnapshot: Equatable {
    var content: String
    var reasoning: String
    var toolCalls: [ChatToolCall]
}

nonisolated struct ChatAssistantResponseAccumulator: Equatable {
    private var content = ""
    private var reasoning = ""
    private var toolCalls: [ChatToolCall] = []

    var snapshot: ChatAssistantResponseSnapshot {
        ChatAssistantResponseSnapshot(
            content: content,
            reasoning: reasoning,
            toolCalls: toolCalls
        )
    }

    mutating func append(
        delta: ChatResponseDelta,
        context: ChatContext
    ) -> ChatResponseDelta? {
        if !delta.toolCalls.isEmpty {
            toolCalls.append(
                contentsOf: delta.toolCalls.map { toolCall in
                    ChatToolCallPresentation.callWithDisplayName(toolCall, context: context)
                }
            )
        }

        let visibleDelta = ChatResponseDelta(
            content: delta.content,
            reasoning: delta.reasoning,
            displayParts: delta.displayParts
        )
        guard !visibleDelta.isEmpty else {
            return nil
        }

        content += visibleDelta.content
        reasoning += visibleDelta.reasoning
        return visibleDelta
    }
}
