//
//  ChatToolCallExecutionResultPlan.swift
//  UniLLMs
//
//  Describes the events and provider message produced by one executed tool call.
//

import Foundation

nonisolated struct ChatToolCallExecutionResultPlan: Equatable {
    var event: ChatToolEvent
    var turnEvents: [ChatTurnEvent]
    var providerMessage: ChatMessage

    init(
        displayToolCall: ChatToolCall,
        providerToolCallID: String,
        toolDisplayName: String,
        result: ToolResult,
        createdAt: Date
    ) {
        self.init(
            event: result.isError
                ? .failed(displayToolCall, message: result.content)
                : .completed(displayToolCall, result: result.content),
            providerToolCallID: providerToolCallID,
            toolDisplayName: toolDisplayName,
            toolStatus: result.status,
            createdAt: createdAt
        )
    }

    init(
        displayToolCall: ChatToolCall,
        providerToolCallID: String,
        toolDisplayName: String,
        failureMessage: String,
        createdAt: Date
    ) {
        self.init(
            event: .failed(displayToolCall, message: failureMessage),
            providerToolCallID: providerToolCallID,
            toolDisplayName: toolDisplayName,
            toolStatus: .error,
            createdAt: createdAt
        )
    }

    private init(
        event: ChatToolEvent,
        providerToolCallID: String,
        toolDisplayName: String,
        toolStatus: ToolExecutionStatus,
        createdAt: Date
    ) {
        self.event = event
        turnEvents = [
            .timelineEvent(.toolEvent(event)),
            .displayDelta(ChatResponseDelta(displayParts: [.toolEvent(event)]))
        ]
        providerMessage = ChatMessage(
            role: .tool,
            content: event.providerMessageContent,
            toolCallID: providerToolCallID,
            toolDisplayName: toolDisplayName,
            toolStatus: toolStatus,
            createdAt: createdAt
        )
    }
}
