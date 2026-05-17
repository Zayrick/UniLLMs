//
//  ChatTimeline.swift
//  UniLLMs
//
//  Defines the persisted chat history timeline and conversion back to provider-facing messages.
//  Created by Codex on 2026/5/16.
//

import Foundation

nonisolated struct ChatTimelineEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        case userMessage(text: String)
        case userMessageWithAttachments(text: String, attachments: [ChatAttachment])
        case assistantReasoning(text: String)
        case assistantContent(markdown: String)
        /// One provider-facing assistant message can request multiple tools.
        case assistantToolCalls([ChatToolCall])
        case toolEvent(ChatToolEvent)
    }

    var id: UUID
    var timestamp: Date
    var kind: Kind

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
    }
}

nonisolated extension ChatTimelineEvent {
    var isEmpty: Bool {
        switch kind {
        case let .userMessage(text),
             let .assistantReasoning(text):
            return text.isEmpty
        case let .userMessageWithAttachments(text, attachments):
            return text.isEmpty && attachments.isEmpty
        case let .assistantContent(markdown):
            return markdown.isEmpty
        case let .assistantToolCalls(toolCalls):
            return toolCalls.isEmpty
        case .toolEvent:
            return false
        }
    }

    static func sortedChronologically(_ events: [ChatTimelineEvent]) -> [ChatTimelineEvent] {
        events.enumerated()
            .sorted {
                if $0.element.timestamp != $1.element.timestamp {
                    return $0.element.timestamp < $1.element.timestamp
                }

                return $0.offset < $1.offset
            }
            .map(\.element)
    }

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

        for event in sortedChronologically(events) {
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
            case let .toolEvent(.started(toolCall)):
                ensureAssistantDraft(startedAt: event.timestamp)
                assistantDraft?.toolCalls.append(toolCall)
                flushAssistantDraft()
            case let .toolEvent(.completed(toolCall, result)):
                flushAssistantDraft()
                messages.append(
                    ChatMessage(
                        id: event.id,
                        role: .tool,
                        content: result,
                        toolCallID: toolCall.id,
                        toolDisplayName: toolCall.presentationName,
                        createdAt: event.timestamp
                    )
                )
            case let .toolEvent(.failed(toolCall, message)):
                flushAssistantDraft()
                messages.append(
                    ChatMessage(
                        id: event.id,
                        role: .tool,
                        content: "Tool execution failed: \(message)",
                        toolCallID: toolCall.id,
                        toolDisplayName: toolCall.presentationName,
                        createdAt: event.timestamp
                    )
                )
            }
        }

        flushAssistantDraft()
        return messages
    }
}

nonisolated private struct AssistantMessageDraft {
    var content = ""
    var reasoning = ""
    var toolCalls: [ChatToolCall] = []
    var createdAt: Date

    nonisolated var message: ChatMessage? {
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

nonisolated struct ChatTimelineAccumulator: Equatable {
    private(set) var events: [ChatTimelineEvent] = []

    init(events: [ChatTimelineEvent] = []) {
        self.events = events
    }

    mutating func append(_ event: ChatTimelineEvent) {
        guard !event.isEmpty else {
            return
        }

        switch event.kind {
        case let .assistantReasoning(text):
            appendText(text, timestamp: event.timestamp, kind: .reasoning)
        case let .assistantContent(markdown):
            appendText(markdown, timestamp: event.timestamp, kind: .content)
        case .userMessage,
             .userMessageWithAttachments,
             .assistantToolCalls,
             .toolEvent:
            events.append(event)
        }
    }

    mutating func appendDisplayDelta(_ delta: ChatResponseDelta, timestamp: Date = Date()) {
        for part in delta.displayParts {
            switch part {
            case let .reasoning(text):
                appendText(text, timestamp: timestamp, kind: .reasoning)
            case let .content(markdown):
                appendText(markdown, timestamp: timestamp, kind: .content)
            case .toolEvent:
                continue
            }
        }
    }

    private enum TextKind {
        case reasoning
        case content
    }

    private mutating func appendText(_ text: String, timestamp: Date, kind: TextKind) {
        guard !text.isEmpty else {
            return
        }

        if let lastIndex = events.indices.last {
            switch (kind, events[lastIndex].kind) {
            case let (.reasoning, .assistantReasoning(existingText)):
                events[lastIndex].kind = .assistantReasoning(text: existingText + text)
                return
            case let (.content, .assistantContent(existingMarkdown)):
                events[lastIndex].kind = .assistantContent(markdown: existingMarkdown + text)
                return
            case (.reasoning, _),
                 (.content, _):
                break
            }
        }

        let eventKind: ChatTimelineEvent.Kind
        switch kind {
        case .reasoning:
            eventKind = .assistantReasoning(text: text)
        case .content:
            eventKind = .assistantContent(markdown: text)
        }
        events.append(ChatTimelineEvent(timestamp: timestamp, kind: eventKind))
    }
}
