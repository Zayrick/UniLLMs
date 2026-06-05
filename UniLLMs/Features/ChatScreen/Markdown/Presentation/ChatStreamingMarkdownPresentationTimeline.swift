//
//  ChatStreamingMarkdownPresentationTimeline.swift
//  UniLLMs
//
//  Tracks streamed Markdown segment slots and their rendered records.
//

import Foundation

struct ChatStreamingMarkdownPresentationTimeline<Record> {
    struct CompletedSegment {
        var markdown: String
        var records: [Record]
    }

    private struct CurrentSegment {
        var markdown: String
        var records: [Record]
    }

    private(set) var completedSegments: [CompletedSegment] = []
    private var currentSegment: CurrentSegment?

    var currentSegmentMarkdown: String? {
        currentSegment?.markdown
    }

    var currentRecords: [Record] {
        currentSegment?.records ?? []
    }

    mutating func reset() {
        completedSegments = []
        currentSegment = nil
    }

    mutating func setFinishedMarkdown(
        _ markdown: String,
        renderRecords: (String) -> [Record]
    ) {
        reset()
        guard !markdown.isEmpty else {
            return
        }

        completedSegments = [
            CompletedSegment(
                markdown: markdown,
                records: renderRecords(markdown)
            )
        ]
    }

    mutating func applyStreamUpdate(
        _ update: ChatMarkdownStreamUpdate,
        commitCurrentSegment: (String, [Record]) -> Bool,
        appendCompletedSegment: (String) -> [Record],
        removeCurrentRecords: ([Record]) -> Void,
        renderCurrentSegment: (String, [Record]) -> [Record]
    ) {
        for segment in update.completedSegments {
            if let currentSegment,
               !currentSegment.records.isEmpty,
               commitCurrentSegment(segment, currentSegment.records) {
                completedSegments.append(
                    CompletedSegment(
                        markdown: segment,
                        records: currentSegment.records
                    )
                )
                self.currentSegment = nil
                continue
            }

            if let currentSegment {
                removeCurrentRecords(currentSegment.records)
            }
            completedSegments.append(
                CompletedSegment(
                    markdown: segment,
                    records: appendCompletedSegment(segment)
                )
            )
            currentSegment = nil
        }

        if let currentMarkdown = update.currentSegment {
            currentSegment = CurrentSegment(
                markdown: currentMarkdown,
                records: renderCurrentSegment(currentMarkdown, currentSegment?.records ?? [])
            )
        } else if let currentSegment {
            removeCurrentRecords(currentSegment.records)
            self.currentSegment = nil
        }
    }

    mutating func removeCurrentRecords(
        _ removeRecords: ([Record]) -> Void
    ) {
        guard let currentSegment else {
            return
        }

        removeRecords(currentSegment.records)
        self.currentSegment = CurrentSegment(
            markdown: currentSegment.markdown,
            records: []
        )
    }

    mutating func rerenderCompletedSegments(
        _ reconcile: (_ markdown: String, _ records: [Record], _ startIndex: Int) -> [Record]
    ) {
        var startIndex = 0
        completedSegments = completedSegments.map { segment in
            let records = reconcile(segment.markdown, segment.records, startIndex)
            startIndex += records.count
            return CompletedSegment(
                markdown: segment.markdown,
                records: records
            )
        }
    }

    mutating func updateCurrentSegment(
        markdown: String,
        records: [Record]
    ) {
        currentSegment = CurrentSegment(
            markdown: markdown,
            records: records
        )
    }
}
