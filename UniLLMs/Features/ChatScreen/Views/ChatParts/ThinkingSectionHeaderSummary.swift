//
//  ThinkingSectionHeaderSummary.swift
//  UniLLMs
//
//  Tracks and formats the finished summary for a thinking section header.
//

import Foundation

struct ThinkingSectionHeaderSummary: Equatable {
    private(set) var reasoningStepCount = 0
    private(set) var toolCallIDs: Set<String> = []

    var isEmpty: Bool {
        reasoningStepCount == 0 && toolCallIDs.isEmpty
    }

    var finishedTitle: String? {
        var parts: [String] = []
        if reasoningStepCount > 0 {
            parts.append("\(reasoningStepCount) \(Self.reasoningStepLabel(for: reasoningStepCount))")
        }
        if toolCallIDs.count > 0 {
            parts.append("\(toolCallIDs.count) \(Self.toolCallLabel(for: toolCallIDs.count))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    mutating func recordReasoningStep() {
        reasoningStepCount += 1
    }

    mutating func recordToolInvocation(callID: String) {
        toolCallIDs.insert(callID)
    }

    private static func reasoningStepLabel(for count: Int) -> String {
        count == 1 ? String(localized: .assistantReasoningStepSingular) : String(localized: .assistantReasoningStepPlural)
    }

    private static func toolCallLabel(for count: Int) -> String {
        count == 1 ? String(localized: .assistantToolCallSingular) : String(localized: .assistantToolCallPlural)
    }
}
