//
//  ChatTimeline.swift
//  UniLLMs
//
//  Defines the persisted chat history timeline and conversion back to provider-facing messages.
//  Created by Zayrick on 2026/5/16.
//

import Foundation

nonisolated struct ChatMessageRevision: Codable, Equatable, Identifiable {
    var id: UUID
    var anchorUserMessageID: UUID
    var archivedAt: Date
    var events: [ChatTimelineRevisionEvent]

    init(
        id: UUID = UUID(),
        anchorUserMessageID: UUID,
        archivedAt: Date = Date(),
        events: [ChatTimelineEvent]
    ) {
        self.id = id
        self.anchorUserMessageID = anchorUserMessageID
        self.archivedAt = archivedAt
        self.events = events.compactMap(ChatTimelineRevisionEvent.init(event:))
    }

    var attachments: [ChatAttachment] {
        events.flatMap(\.attachments)
    }
}

nonisolated struct ChatTimelineRevisionEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        case userMessage(text: String)
        case userMessageWithAttachments(text: String, attachments: [ChatAttachment])
        case assistantReasoning(text: String)
        case assistantRawText(rawText: String)
        case assistantError(message: String)
        case assistantToolCalls([ChatToolCall])
        case toolEvent(ChatToolEvent)

        private enum CodingKeys: String, CodingKey {
            case userMessage
            case userMessageWithAttachments
            case assistantReasoning
            case assistantRawText
            case assistantError
            case assistantToolCalls
            case toolEvent
        }

        private enum TextCodingKeys: String, CodingKey {
            case rawText
            case text
        }

        private enum UserMessageWithAttachmentsCodingKeys: String, CodingKey {
            case text
            case attachments
        }

        private enum SingleValueCodingKeys: String, CodingKey {
            case value = "_0"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.userMessage) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .userMessage)
                self = .userMessage(text: try nested.decode(String.self, forKey: .text))
            } else if container.contains(.userMessageWithAttachments) {
                let nested = try container.nestedContainer(
                    keyedBy: UserMessageWithAttachmentsCodingKeys.self,
                    forKey: .userMessageWithAttachments
                )
                self = .userMessageWithAttachments(
                    text: try nested.decode(String.self, forKey: .text),
                    attachments: try nested.decode([ChatAttachment].self, forKey: .attachments)
                )
            } else if container.contains(.assistantReasoning) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantReasoning)
                self = .assistantReasoning(text: try nested.decode(String.self, forKey: .text))
            } else if container.contains(.assistantRawText) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantRawText)
                self = .assistantRawText(rawText: try nested.decode(String.self, forKey: .rawText))
            } else if container.contains(.assistantError) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantError)
                self = .assistantError(message: try nested.decode(String.self, forKey: .text))
            } else if container.contains(.assistantToolCalls) {
                let nested = try container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .assistantToolCalls)
                self = .assistantToolCalls(try nested.decode([ChatToolCall].self, forKey: .value))
            } else if container.contains(.toolEvent) {
                let nested = try container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .toolEvent)
                self = .toolEvent(try nested.decode(ChatToolEvent.self, forKey: .value))
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown chat timeline revision event kind."
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .userMessage(text):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .userMessage)
                try nested.encode(text, forKey: .text)
            case let .userMessageWithAttachments(text, attachments):
                var nested = container.nestedContainer(
                    keyedBy: UserMessageWithAttachmentsCodingKeys.self,
                    forKey: .userMessageWithAttachments
                )
                try nested.encode(text, forKey: .text)
                try nested.encode(attachments, forKey: .attachments)
            case let .assistantReasoning(text):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantReasoning)
                try nested.encode(text, forKey: .text)
            case let .assistantRawText(rawText):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantRawText)
                try nested.encode(rawText, forKey: .rawText)
            case let .assistantError(message):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantError)
                try nested.encode(message, forKey: .text)
            case let .assistantToolCalls(toolCalls):
                var nested = container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .assistantToolCalls)
                try nested.encode(toolCalls, forKey: .value)
            case let .toolEvent(toolEvent):
                var nested = container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .toolEvent)
                try nested.encode(toolEvent, forKey: .value)
            }
        }
    }

    var id: UUID
    var timestamp: Date
    var kind: Kind

    init?(
        event: ChatTimelineEvent
    ) {
        switch event.kind {
        case let .userMessage(text):
            kind = .userMessage(text: text)
        case let .userMessageWithAttachments(text, attachments):
            kind = .userMessageWithAttachments(text: text, attachments: attachments)
        case let .assistantReasoning(text):
            kind = .assistantReasoning(text: text)
        case let .assistantRawText(rawText):
            kind = .assistantRawText(rawText: rawText)
        case let .assistantError(message):
            kind = .assistantError(message: message)
        case let .assistantToolCalls(toolCalls):
            kind = .assistantToolCalls(toolCalls)
        case let .toolEvent(toolEvent):
            kind = .toolEvent(toolEvent)
        case .messageRevision:
            return nil
        }

        id = event.id
        timestamp = event.timestamp
    }

    var timelineEvent: ChatTimelineEvent {
        let eventKind: ChatTimelineEvent.Kind
        switch kind {
        case let .userMessage(text):
            eventKind = .userMessage(text: text)
        case let .userMessageWithAttachments(text, attachments):
            eventKind = .userMessageWithAttachments(text: text, attachments: attachments)
        case let .assistantReasoning(text):
            eventKind = .assistantReasoning(text: text)
        case let .assistantRawText(rawText):
            eventKind = .assistantRawText(rawText: rawText)
        case let .assistantError(message):
            eventKind = .assistantError(message: message)
        case let .assistantToolCalls(toolCalls):
            eventKind = .assistantToolCalls(toolCalls)
        case let .toolEvent(toolEvent):
            eventKind = .toolEvent(toolEvent)
        }

        return ChatTimelineEvent(
            id: id,
            timestamp: timestamp,
            kind: eventKind
        )
    }
}

nonisolated extension ChatTimelineRevisionEvent {
    var attachments: [ChatAttachment] {
        switch kind {
        case let .userMessageWithAttachments(_, attachments):
            return attachments
        case .userMessage,
             .assistantReasoning,
             .assistantRawText,
             .assistantError,
             .assistantToolCalls,
             .toolEvent:
            return []
        }
    }
}

nonisolated struct ChatTimelineEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        case userMessage(text: String)
        case userMessageWithAttachments(text: String, attachments: [ChatAttachment])
        case assistantReasoning(text: String)
        case assistantRawText(rawText: String)
        case assistantError(message: String)
        /// One provider-facing assistant message can request multiple tools.
        case assistantToolCalls([ChatToolCall])
        case toolEvent(ChatToolEvent)
        case messageRevision(ChatMessageRevision)

        private enum CodingKeys: String, CodingKey {
            case userMessage
            case userMessageWithAttachments
            case assistantReasoning
            case assistantRawText
            case assistantError
            case assistantToolCalls
            case toolEvent
            case messageRevision
        }

        private enum TextCodingKeys: String, CodingKey {
            case rawText
            case text
        }

        private enum UserMessageWithAttachmentsCodingKeys: String, CodingKey {
            case text
            case attachments
        }

        private enum SingleValueCodingKeys: String, CodingKey {
            case value = "_0"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.userMessage) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .userMessage)
                self = .userMessage(text: try nested.decode(String.self, forKey: .text))
            } else if container.contains(.userMessageWithAttachments) {
                let nested = try container.nestedContainer(
                    keyedBy: UserMessageWithAttachmentsCodingKeys.self,
                    forKey: .userMessageWithAttachments
                )
                self = .userMessageWithAttachments(
                    text: try nested.decode(String.self, forKey: .text),
                    attachments: try nested.decode([ChatAttachment].self, forKey: .attachments)
                )
            } else if container.contains(.assistantReasoning) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantReasoning)
                self = .assistantReasoning(text: try nested.decode(String.self, forKey: .text))
            } else if container.contains(.assistantRawText) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantRawText)
                self = .assistantRawText(rawText: try nested.decode(String.self, forKey: .rawText))
            } else if container.contains(.assistantError) {
                let nested = try container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantError)
                self = .assistantError(message: try nested.decode(String.self, forKey: .text))
            } else if container.contains(.assistantToolCalls) {
                let nested = try container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .assistantToolCalls)
                self = .assistantToolCalls(try nested.decode([ChatToolCall].self, forKey: .value))
            } else if container.contains(.toolEvent) {
                let nested = try container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .toolEvent)
                self = .toolEvent(try nested.decode(ChatToolEvent.self, forKey: .value))
            } else if container.contains(.messageRevision) {
                let nested = try container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .messageRevision)
                self = .messageRevision(try nested.decode(ChatMessageRevision.self, forKey: .value))
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown chat timeline event kind."
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .userMessage(text):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .userMessage)
                try nested.encode(text, forKey: .text)
            case let .userMessageWithAttachments(text, attachments):
                var nested = container.nestedContainer(
                    keyedBy: UserMessageWithAttachmentsCodingKeys.self,
                    forKey: .userMessageWithAttachments
                )
                try nested.encode(text, forKey: .text)
                try nested.encode(attachments, forKey: .attachments)
            case let .assistantReasoning(text):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantReasoning)
                try nested.encode(text, forKey: .text)
            case let .assistantRawText(rawText):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantRawText)
                try nested.encode(rawText, forKey: .rawText)
            case let .assistantError(message):
                var nested = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .assistantError)
                try nested.encode(message, forKey: .text)
            case let .assistantToolCalls(toolCalls):
                var nested = container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .assistantToolCalls)
                try nested.encode(toolCalls, forKey: .value)
            case let .toolEvent(toolEvent):
                var nested = container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .toolEvent)
                try nested.encode(toolEvent, forKey: .value)
            case let .messageRevision(revision):
                var nested = container.nestedContainer(keyedBy: SingleValueCodingKeys.self, forKey: .messageRevision)
                try nested.encode(revision, forKey: .value)
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
    var attachments: [ChatAttachment] {
        switch kind {
        case let .userMessageWithAttachments(_, attachments):
            return attachments
        case let .messageRevision(revision):
            return revision.attachments
        case .userMessage,
             .assistantReasoning,
             .assistantRawText,
             .assistantError,
             .assistantToolCalls,
             .toolEvent:
            return []
        }
    }

    var isUserMessage: Bool {
        switch kind {
        case .userMessage,
             .userMessageWithAttachments:
            return true
        case .assistantReasoning,
             .assistantRawText,
             .assistantError,
             .assistantToolCalls,
             .toolEvent,
             .messageRevision:
            return false
        }
    }

    var isEmpty: Bool {
        switch kind {
        case let .userMessage(text),
             let .assistantReasoning(text):
            return text.isEmpty
        case let .userMessageWithAttachments(text, attachments):
            return text.isEmpty && attachments.isEmpty
        case let .assistantRawText(rawText):
            return rawText.isEmpty
        case let .assistantError(message):
            return message.isEmpty
        case let .assistantToolCalls(toolCalls):
            return toolCalls.isEmpty
        case let .messageRevision(revision):
            return revision.events.isEmpty
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

    static func attachments(from events: [ChatTimelineEvent]) -> [ChatAttachment] {
        events.flatMap(\.attachments)
    }

    static func messageRevisions(from events: [ChatTimelineEvent]) -> [UUID: [ChatMessageRevision]] {
        var revisionsByAnchorID: [UUID: [ChatMessageRevision]] = [:]
        let indexedRevisions = events.enumerated().compactMap { offset, event -> (Int, ChatMessageRevision)? in
            guard case let .messageRevision(revision) = event.kind else {
                return nil
            }

            return (offset, revision)
        }
        .sorted { lhs, rhs in
            if lhs.1.archivedAt != rhs.1.archivedAt {
                return lhs.1.archivedAt < rhs.1.archivedAt
            }

            return lhs.0 < rhs.0
        }

        for (_, revision) in indexedRevisions {
            revisionsByAnchorID[revision.anchorUserMessageID, default: []].append(revision)
        }
        return revisionsByAnchorID
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
            case let .assistantRawText(rawText):
                guard !rawText.isEmpty else {
                    continue
                }
                ensureAssistantDraft(startedAt: event.timestamp)
                assistantDraft?.content += rawText
            case .assistantError:
                flushAssistantDraft()
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
        case let .assistantRawText(rawText):
            appendText(rawText, timestamp: event.timestamp, kind: .rawText)
        case .assistantError:
            events.append(event)
        case .userMessage,
             .userMessageWithAttachments,
             .assistantToolCalls,
             .toolEvent,
             .messageRevision:
            events.append(event)
        }
    }

    mutating func appendDisplayDelta(_ delta: ChatResponseDelta, timestamp: Date = Date()) {
        for part in delta.displayParts {
            switch part {
            case let .reasoning(text):
                appendText(text, timestamp: timestamp, kind: .reasoning)
            case let .rawText(rawText):
                appendText(rawText, timestamp: timestamp, kind: .rawText)
            case .toolEvent:
                continue
            }
        }
    }

    private enum TextKind {
        case reasoning
        case rawText
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
            case let (.rawText, .assistantRawText(existingRawText)):
                events[lastIndex].kind = .assistantRawText(rawText: existingRawText + text)
                return
            case (.reasoning, _),
                 (.rawText, _):
                break
            }
        }

        let eventKind: ChatTimelineEvent.Kind
        switch kind {
        case .reasoning:
            eventKind = .assistantReasoning(text: text)
        case .rawText:
            eventKind = .assistantRawText(rawText: text)
        }
        events.append(ChatTimelineEvent(timestamp: timestamp, kind: eventKind))
    }
}
