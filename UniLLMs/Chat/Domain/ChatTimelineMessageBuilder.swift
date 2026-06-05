//
//  ChatTimelineMessageBuilder.swift
//  UniLLMs
//
//  Converts persisted timeline events back into provider-facing chat messages.
//

import Foundation

nonisolated struct ChatTimelineMessageBuilder {
    static func messages(from events: [ChatTimelineEvent]) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var assistantDraft: AssistantMessageDraft?

        func ensureAssistantDraft(startedAt timestamp: Date) {
            if assistantDraft == nil {
                assistantDraft = AssistantMessageDraft(createdAt: timestamp)
            }
        }

        func flushAssistantDraft() {
            guard let draft = assistantDraft,
                  let message = draft.message else {
                assistantDraft = nil
                return
            }

            messages.append(message)
            assistantDraft = nil
        }

        for event in ChatTimelineEvent.sortedChronologically(events) {
            switch event.kind {
            case let .userMessage(text):
                flushAssistantDraft()
                messages.append(
                    ChatMessage(
                        id: event.id,
                        role: .user,
                        content: text,
                        createdAt: event.timestamp
                    )
                )
            case let .userMessageWithAttachments(text, attachments):
                flushAssistantDraft()
                messages.append(
                    ChatMessage(
                        id: event.id,
                        role: .user,
                        content: text,
                        attachments: attachments,
                        createdAt: event.timestamp
                    )
                )
            case let .assistantReasoning(text):
                guard !text.isEmpty else {
                    continue
                }
                ensureAssistantDraft(startedAt: event.timestamp)
                assistantDraft?.reasoning += text
            case let .assistantContent(markdown):
                guard !markdown.isEmpty else {
                    continue
                }
                ensureAssistantDraft(startedAt: event.timestamp)
                assistantDraft?.content += markdown
            case let .assistantToolCalls(toolCalls):
                ensureAssistantDraft(startedAt: event.timestamp)
                assistantDraft?.toolCalls.append(contentsOf: toolCalls)
                flushAssistantDraft()
            case let .toolEvent(toolEvent):
                switch toolEvent {
                case let .started(toolCall):
                    ensureAssistantDraft(startedAt: event.timestamp)
                    assistantDraft?.toolCalls.append(toolCall)
                    flushAssistantDraft()
                case let .completed(toolCall, _),
                     let .failed(toolCall, _):
                    flushAssistantDraft()
                    messages.append(
                        ChatMessage(
                            id: event.id,
                            role: .tool,
                            content: toolEvent.providerMessageContent,
                            toolCallID: toolCall.id,
                            toolDisplayName: toolCall.presentationName,
                            toolStatus: toolEvent.toolStatus,
                            createdAt: event.timestamp
                        )
                    )
                }
            case .messageRevision:
                continue
            }
        }

        flushAssistantDraft()
        return messages
    }
}

nonisolated private extension ChatToolEvent {
    var toolStatus: ToolExecutionStatus {
        switch self {
        case .started,
             .completed:
            return .success
        case .failed:
            return .error
        }
    }
}

nonisolated private struct AssistantMessageDraft {
    var content = ""
    var reasoning = ""
    var toolCalls: [ChatToolCall] = []
    var createdAt: Date

    var message: ChatMessage? {
        guard !content.isEmpty || !reasoning.isEmpty || !toolCalls.isEmpty else {
            return nil
        }

        return ChatMessage(
            role: .assistant,
            content: content,
            reasoning: reasoning,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            createdAt: createdAt
        )
    }
}
