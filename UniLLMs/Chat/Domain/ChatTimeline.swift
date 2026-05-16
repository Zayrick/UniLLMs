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
        case assistantReasoning(text: String)
        case assistantContent(markdown: String)
        case toolCallStarted(
            callID: String,
            toolID: String,
            displayName: String,
            arguments: String
        )
        case toolCallCompleted(
            callID: String,
            toolID: String,
            displayName: String,
            result: String
        )
        case toolCallFailed(
            callID: String,
            toolID: String,
            displayName: String,
            message: String
        )

        private enum Name: String, Codable {
            case userMessage
            case assistantReasoning
            case assistantContent
            case toolCallStarted
            case toolCallCompleted
            case toolCallFailed
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case text
            case markdown
            case callID
            case toolID
            case displayName
            case arguments
            case result
            case message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Name.self, forKey: .kind) {
            case .userMessage:
                self = .userMessage(
                    text: try container.decode(String.self, forKey: .text)
                )
            case .assistantReasoning:
                self = .assistantReasoning(
                    text: try container.decode(String.self, forKey: .text)
                )
            case .assistantContent:
                self = .assistantContent(
                    markdown: try container.decode(String.self, forKey: .markdown)
                )
            case .toolCallStarted:
                self = .toolCallStarted(
                    callID: try container.decode(String.self, forKey: .callID),
                    toolID: try container.decode(String.self, forKey: .toolID),
                    displayName: try container.decode(String.self, forKey: .displayName),
                    arguments: try container.decode(String.self, forKey: .arguments)
                )
            case .toolCallCompleted:
                self = .toolCallCompleted(
                    callID: try container.decode(String.self, forKey: .callID),
                    toolID: try container.decode(String.self, forKey: .toolID),
                    displayName: try container.decode(String.self, forKey: .displayName),
                    result: try container.decode(String.self, forKey: .result)
                )
            case .toolCallFailed:
                self = .toolCallFailed(
                    callID: try container.decode(String.self, forKey: .callID),
                    toolID: try container.decode(String.self, forKey: .toolID),
                    displayName: try container.decode(String.self, forKey: .displayName),
                    message: try container.decode(String.self, forKey: .message)
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .userMessage(text):
                try container.encode(Name.userMessage, forKey: .kind)
                try container.encode(text, forKey: .text)
            case let .assistantReasoning(text):
                try container.encode(Name.assistantReasoning, forKey: .kind)
                try container.encode(text, forKey: .text)
            case let .assistantContent(markdown):
                try container.encode(Name.assistantContent, forKey: .kind)
                try container.encode(markdown, forKey: .markdown)
            case let .toolCallStarted(callID, toolID, displayName, arguments):
                try container.encode(Name.toolCallStarted, forKey: .kind)
                try container.encode(callID, forKey: .callID)
                try container.encode(toolID, forKey: .toolID)
                try container.encode(displayName, forKey: .displayName)
                try container.encode(arguments, forKey: .arguments)
            case let .toolCallCompleted(callID, toolID, displayName, result):
                try container.encode(Name.toolCallCompleted, forKey: .kind)
                try container.encode(callID, forKey: .callID)
                try container.encode(toolID, forKey: .toolID)
                try container.encode(displayName, forKey: .displayName)
                try container.encode(result, forKey: .result)
            case let .toolCallFailed(callID, toolID, displayName, message):
                try container.encode(Name.toolCallFailed, forKey: .kind)
                try container.encode(callID, forKey: .callID)
                try container.encode(toolID, forKey: .toolID)
                try container.encode(displayName, forKey: .displayName)
                try container.encode(message, forKey: .message)
            }
        }
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
        case let .assistantContent(markdown):
            return markdown.isEmpty
        case .toolCallStarted,
             .toolCallCompleted,
             .toolCallFailed:
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
            case let .toolCallStarted(callID, toolID, displayName, arguments):
                ensureAssistantDraft(startedAt: event.timestamp)
                assistantDraft?.toolCalls.append(
                    ChatToolCall(
                        id: callID,
                        toolID: toolID,
                        arguments: arguments,
                        displayName: displayName
                    )
                )
            case let .toolCallCompleted(callID, toolID, displayName, result):
                flushAssistantDraft()
                messages.append(
                    ChatMessage(
                        id: event.id,
                        role: .tool,
                        content: result,
                        toolCallID: callID,
                        toolDisplayName: displayName.isEmpty ? toolID : displayName,
                        createdAt: event.timestamp
                    )
                )
            case let .toolCallFailed(callID, toolID, displayName, message):
                flushAssistantDraft()
                messages.append(
                    ChatMessage(
                        id: event.id,
                        role: .tool,
                        content: "Tool execution failed: \(message)",
                        toolCallID: callID,
                        toolDisplayName: displayName.isEmpty ? toolID : displayName,
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
             .toolCallStarted,
             .toolCallCompleted,
             .toolCallFailed:
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
