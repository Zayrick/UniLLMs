//
//  ChatToolCallExecutor.swift
//  UniLLMs
//
//  Executes assistant tool calls and converts tool results into chat turn events.
//

import Foundation

final class ChatToolCallExecutor {
    private let toolManager: ToolManager
    private let clock: any AppClock

    init(
        toolManager: ToolManager,
        clock: any AppClock = SystemAppClock()
    ) {
        self.toolManager = toolManager
        self.clock = clock
    }

    func execute(
        _ toolCalls: [ChatToolCall],
        context: ChatContext,
        emit: (ChatTurnEvent) -> Void
    ) async -> [ChatMessage] {
        var messages: [ChatMessage] = []
        let executionContext = ToolExecutionContext(session: context.session)

        for toolCall in toolCalls {
            let toolDisplayName = ChatToolCallPresentation.resolvedDisplayName(
                for: toolCall,
                context: context
            )
            let displayToolCall = ChatToolCallPresentation.callWithDisplayName(
                toolCall,
                displayName: toolDisplayName
            )

            do {
                let call = ToolCall(
                    id: toolCall.id,
                    toolID: toolCall.toolID,
                    arguments: try Self.parseArguments(toolCall.arguments)
                )
                let result = try await toolManager.execute(call: call, context: executionContext)
                let plan = ChatToolCallExecutionResultPlan(
                    displayToolCall: displayToolCall,
                    providerToolCallID: toolCall.id,
                    toolDisplayName: toolDisplayName,
                    result: result,
                    createdAt: clock.now
                )
                plan.turnEvents.forEach(emit)
                messages.append(plan.providerMessage)
            } catch {
                let plan = ChatToolCallExecutionResultPlan(
                    displayToolCall: displayToolCall,
                    providerToolCallID: toolCall.id,
                    toolDisplayName: toolDisplayName,
                    failureMessage: error.localizedDescription,
                    createdAt: clock.now
                )
                plan.turnEvents.forEach(emit)
                messages.append(plan.providerMessage)
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
}

nonisolated enum ChatToolCallPresentation {
    static func displayName(for toolID: String, context: ChatContext) -> String {
        guard let definition = context.availableTools.first(where: { $0.id == toolID }) else {
            return toolID
        }

        return definition.presentationName
    }

    static func callWithDisplayName(_ toolCall: ChatToolCall, context: ChatContext) -> ChatToolCall {
        callWithDisplayName(
            toolCall,
            displayName: displayName(for: toolCall.toolID, context: context)
        )
    }

    static func callWithDisplayName(_ toolCall: ChatToolCall, displayName: String) -> ChatToolCall {
        ChatToolCall(
            id: toolCall.id,
            toolID: toolCall.toolID,
            arguments: toolCall.arguments,
            displayName: displayName,
            providerMetadata: toolCall.providerMetadata
        )
    }

    static func resolvedDisplayName(for toolCall: ChatToolCall, context: ChatContext) -> String {
        let storedDisplayName = toolCall.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return storedDisplayName.isEmpty ? displayName(for: toolCall.toolID, context: context) : storedDisplayName
    }
}

enum ToolExecutionLoopError: LocalizedError, Equatable {
    case invalidArguments
    case exceededMaximumIterations(Int)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return String(localized: .runtimeErrorInvalidToolArguments)
        case let .exceededMaximumIterations(maximumIterations):
            return String(localized: .runtimeErrorToolIterationLimitFormat(maximumIterations))
        }
    }
}
