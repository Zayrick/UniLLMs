//
//  ServerSentEventLine.swift
//  UniLLMs
//
//  Shared parsing helpers for single-line server-sent event streams.
//

import Foundation

nonisolated enum ServerSentEventLine {
    static func dataPayload(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty,
              !trimmedLine.hasPrefix(":"),
              trimmedLine.hasPrefix("data:") else {
            return nil
        }

        let dataPrefixEndIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 5)
        return trimmedLine[dataPrefixEndIndex...]
            .trimmingCharacters(in: .whitespaces)
    }

    static func isDone(_ line: String) -> Bool {
        dataPayload(from: line) == "[DONE]"
    }
}
