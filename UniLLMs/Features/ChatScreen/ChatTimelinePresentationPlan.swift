//
//  ChatTimelinePresentationPlan.swift
//  UniLLMs
//
//  Converts persisted chat timeline events into rows the chat screen can render.
//

import Foundation

struct ChatTimelinePresentationPlan: Equatable {
    enum Row: Equatable {
        case userMessage(id: UUID, text: String, attachments: [ChatAttachment])
        case assistantResponse(steps: [AssistantStep])
    }

    enum AssistantStep: Equatable {
        case reasoning(String)
        case contentMarkdown(String)
        case toolEvent(ChatToolEvent)
    }

    var rows: [Row]

    init(events: [ChatTimelineEvent]) {
        rows = Self.makeRows(from: events)
    }

    private static func makeRows(from events: [ChatTimelineEvent]) -> [Row] {
        var rows: [Row] = []
        var assistantSteps: [AssistantStep] = []

        func flushAssistantSteps() {
            guard !assistantSteps.isEmpty else {
                return
            }

            rows.append(.assistantResponse(steps: assistantSteps))
            assistantSteps.removeAll()
        }

        for event in ChatTimelineEvent.sortedChronologically(events) {
            switch event.kind {
            case let .userMessage(text):
                flushAssistantSteps()
                rows.append(.userMessage(id: event.id, text: text, attachments: []))
            case let .userMessageWithAttachments(text, attachments):
                flushAssistantSteps()
                rows.append(.userMessage(id: event.id, text: text, attachments: attachments))
            case let .assistantReasoning(text):
                assistantSteps.append(.reasoning(text))
            case let .assistantContent(markdown):
                assistantSteps.append(.contentMarkdown(markdown))
            case let .assistantToolCalls(toolCalls):
                assistantSteps.append(contentsOf: toolCalls.map { .toolEvent(.started($0)) })
            case let .toolEvent(toolEvent):
                assistantSteps.append(.toolEvent(toolEvent))
            case .messageRevision:
                continue
            }
        }

        flushAssistantSteps()
        return rows
    }
}
