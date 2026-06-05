//
//  ChatAssistantResponseTimelinePresentationState.swift
//  UniLLMs
//
//  Owns the semantic timeline state for one assistant response.
//

import Foundation

nonisolated struct ChatAssistantResponseTimelinePresentationState: Equatable {
    nonisolated struct SegmentID: Hashable, Equatable, CustomStringConvertible {
        let rawValue: Int

        init(_ rawValue: Int) {
            self.rawValue = rawValue
        }

        var description: String {
            "segment_\(rawValue)"
        }
    }

    private enum SegmentKind: Equatable {
        case thinking
        case content
    }

    private struct Segment: Equatable {
        var id: SegmentID
        var kind: SegmentKind
    }

    nonisolated enum ToolInvocationState: Equatable {
        case running
        case completed
        case failed(message: String)
    }

    nonisolated struct ToolInvocationPresentation: Equatable {
        var callID: String
        var displayName: String
        var state: ToolInvocationState
        var detail: String
    }

    nonisolated enum Action: Equatable {
        case createThinkingSegment(SegmentID)
        case appendReasoning(segmentID: SegmentID, text: String)
        case finishThinkingSegment(SegmentID, animated: Bool)
        case createContentSegment(SegmentID)
        case appendContentMarkdown(segmentID: SegmentID, markdown: String)
        case setFinishedContentMarkdown(segmentID: SegmentID, markdown: String)
        case appendToolInvocation(
            segmentID: SegmentID,
            invocation: ToolInvocationPresentation
        )
        case finishContentSegment(SegmentID)
    }

    private var segments: [Segment] = []
    private(set) var rawContentMarkdown = ""
    private(set) var isResponseFinished = false

    private var activeThinkingSegmentID: SegmentID?
    private var toolSectionIDsByCallID: [String: SegmentID] = [:]
    private var nextSegmentRawValue = 0

    var isEmpty: Bool {
        segments.isEmpty
    }

    var shouldShowCopyMarkdownButton: Bool {
        isResponseFinished && !rawContentMarkdown.isEmpty
    }

    mutating func appendDisplayParts(_ parts: [ChatResponseDisplayPart]) -> [Action] {
        let visibleParts = parts.filter { !$0.isEmpty }
        guard !visibleParts.isEmpty else {
            return []
        }

        isResponseFinished = false

        var actions: [Action] = []
        for part in visibleParts {
            actions.append(contentsOf: appendDisplayPartWithoutFiltering(part))
        }
        return actions
    }

    mutating func appendStoredContentMarkdown(_ markdown: String) -> [Action] {
        guard !markdown.isEmpty else {
            return []
        }

        isResponseFinished = false
        rawContentMarkdown += markdown

        var actions = finishActiveThinkingSection(animated: false)
        let segmentID = appendSegment(kind: .content)
        actions.append(.createContentSegment(segmentID))
        actions.append(.setFinishedContentMarkdown(segmentID: segmentID, markdown: markdown))
        return actions
    }

    mutating func setError() -> [Action] {
        guard !isResponseFinished else {
            return []
        }

        isResponseFinished = true
        return finishContentSegments() + finishAllThinkingSections(animated: true)
    }

    mutating func finishStreamingContent() -> [Action] {
        guard !isResponseFinished else {
            return []
        }

        isResponseFinished = true
        return finishContentSegments() + finishAllThinkingSections(animated: true)
    }

    private mutating func appendDisplayPartWithoutFiltering(_ part: ChatResponseDisplayPart) -> [Action] {
        switch part {
        case let .reasoning(text):
            return appendReasoningTimelinePart(text)
        case let .content(markdown):
            return appendContentTimelinePart(markdown)
        case let .toolEvent(event):
            return appendToolTimelineEvent(event)
        }
    }

    private mutating func appendReasoningTimelinePart(_ text: String) -> [Action] {
        guard !text.isEmpty else {
            return []
        }

        var actions: [Action] = []
        let segmentID = ensureActiveThinkingSection(actions: &actions)
        actions.append(.appendReasoning(segmentID: segmentID, text: text))
        return actions
    }

    private mutating func appendContentTimelinePart(_ markdown: String) -> [Action] {
        guard !markdown.isEmpty else {
            return []
        }

        var actions = finishActiveThinkingSection(animated: true)
        rawContentMarkdown += markdown

        if let lastSegment = segments.last,
           lastSegment.kind == .content {
            actions.append(.appendContentMarkdown(segmentID: lastSegment.id, markdown: markdown))
            return actions
        }

        let segmentID = appendSegment(kind: .content)
        actions.append(.createContentSegment(segmentID))
        actions.append(.appendContentMarkdown(segmentID: segmentID, markdown: markdown))
        return actions
    }

    private mutating func appendToolTimelineEvent(_ event: ChatToolEvent) -> [Action] {
        var actions: [Action] = []

        switch event {
        case let .started(toolCall):
            let segmentID = ensureActiveThinkingSection(actions: &actions)
            toolSectionIDsByCallID[toolCall.id] = segmentID
            actions.append(
                .appendToolInvocation(
                    segmentID: segmentID,
                    invocation: ToolInvocationPresentation(
                        callID: toolCall.id,
                        displayName: toolCall.presentationName,
                        state: .running,
                        detail: toolCall.serializedArguments
                    )
                )
            )
        case let .completed(toolCall, result):
            let segmentID = toolSectionID(for: toolCall, actions: &actions)
            actions.append(
                .appendToolInvocation(
                    segmentID: segmentID,
                    invocation: ToolInvocationPresentation(
                        callID: toolCall.id,
                        displayName: toolCall.presentationName,
                        state: .completed,
                        detail: result
                    )
                )
            )
        case let .failed(toolCall, message):
            let segmentID = toolSectionID(for: toolCall, actions: &actions)
            actions.append(
                .appendToolInvocation(
                    segmentID: segmentID,
                    invocation: ToolInvocationPresentation(
                        callID: toolCall.id,
                        displayName: toolCall.presentationName,
                        state: .failed(message: message),
                        detail: message
                    )
                )
            )
        }

        return actions
    }

    private mutating func toolSectionID(
        for toolCall: ChatToolCall,
        actions: inout [Action]
    ) -> SegmentID {
        let segmentID = toolSectionIDsByCallID[toolCall.id] ?? ensureActiveThinkingSection(
            actions: &actions
        )
        toolSectionIDsByCallID[toolCall.id] = segmentID
        return segmentID
    }

    private mutating func ensureActiveThinkingSection(actions: inout [Action]) -> SegmentID {
        if let activeThinkingSegmentID {
            return activeThinkingSegmentID
        }

        let segmentID = appendSegment(kind: .thinking)
        activeThinkingSegmentID = segmentID
        actions.append(.createThinkingSegment(segmentID))
        return segmentID
    }

    private mutating func finishActiveThinkingSection(animated: Bool) -> [Action] {
        guard let activeThinkingSegmentID else {
            return []
        }

        self.activeThinkingSegmentID = nil
        return [.finishThinkingSegment(activeThinkingSegmentID, animated: animated)]
    }

    private mutating func finishAllThinkingSections(animated: Bool) -> [Action] {
        activeThinkingSegmentID = nil
        return segments.compactMap { segment in
            guard segment.kind == .thinking else {
                return nil
            }
            return .finishThinkingSegment(segment.id, animated: animated)
        }
    }

    private func finishContentSegments() -> [Action] {
        segments.compactMap { segment in
            guard segment.kind == .content else {
                return nil
            }
            return .finishContentSegment(segment.id)
        }
    }

    private mutating func appendSegment(kind: SegmentKind) -> SegmentID {
        let segmentID = SegmentID(nextSegmentRawValue)
        nextSegmentRawValue += 1
        segments.append(
            Segment(
                id: segmentID,
                kind: kind
            )
        )
        return segmentID
    }
}
