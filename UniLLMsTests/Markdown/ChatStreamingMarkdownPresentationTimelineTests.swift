//
//  ChatStreamingMarkdownPresentationTimelineTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatStreamingMarkdownPresentationTimelineTests: XCTestCase {
    func testCompletedSegmentPromotesCurrentRecordsWhenCommitSucceeds() {
        var timeline = ChatStreamingMarkdownPresentationTimeline<Int>()
        timeline.applyStreamUpdate(
            update(currentSegment: "draft"),
            commitCurrentSegment: { _, _ in false },
            appendCompletedSegment: { _ in XCTFail("Should not append completed segment."); return [] },
            removeCurrentRecords: { _ in XCTFail("Should not remove records.") },
            renderCurrentSegment: { markdown, records in
                XCTAssertEqual(markdown, "draft")
                XCTAssertTrue(records.isEmpty)
                return [10]
            }
        )

        timeline.applyStreamUpdate(
            update(completedSegments: ["draft"]),
            commitCurrentSegment: { markdown, records in
                XCTAssertEqual(markdown, "draft")
                XCTAssertEqual(records, [10])
                return true
            },
            appendCompletedSegment: { _ in XCTFail("Should reuse current records."); return [] },
            removeCurrentRecords: { _ in XCTFail("Should not remove committed records.") },
            renderCurrentSegment: { _, _ in XCTFail("Should not render a current segment."); return [] }
        )

        XCTAssertEqual(timeline.completedSegments.count, 1)
        XCTAssertEqual(timeline.completedSegments[0].markdown, "draft")
        XCTAssertEqual(timeline.completedSegments[0].records, [10])
        XCTAssertNil(timeline.currentSegmentMarkdown)
        XCTAssertTrue(timeline.currentRecords.isEmpty)
    }

    func testCompletedSegmentRemovesCurrentAndAppendsWhenCommitFails() {
        var timeline = ChatStreamingMarkdownPresentationTimeline<Int>()
        timeline.applyStreamUpdate(
            update(currentSegment: "partial"),
            commitCurrentSegment: { _, _ in false },
            appendCompletedSegment: { _ in XCTFail("Should not append completed segment."); return [] },
            removeCurrentRecords: { _ in XCTFail("Should not remove records.") },
            renderCurrentSegment: { _, _ in [4] }
        )

        var removedRecords: [[Int]] = []
        timeline.applyStreamUpdate(
            update(completedSegments: ["completed"]),
            commitCurrentSegment: { markdown, records in
                XCTAssertEqual(markdown, "completed")
                XCTAssertEqual(records, [4])
                return false
            },
            appendCompletedSegment: { markdown in
                XCTAssertEqual(markdown, "completed")
                return [8, 9]
            },
            removeCurrentRecords: { records in
                removedRecords.append(records)
            },
            renderCurrentSegment: { _, _ in XCTFail("Should not render a current segment."); return [] }
        )

        XCTAssertEqual(removedRecords, [[4]])
        XCTAssertEqual(timeline.completedSegments.count, 1)
        XCTAssertEqual(timeline.completedSegments[0].markdown, "completed")
        XCTAssertEqual(timeline.completedSegments[0].records, [8, 9])
        XCTAssertNil(timeline.currentSegmentMarkdown)
    }

    func testNilCurrentSegmentClearsCurrentRecords() {
        var timeline = ChatStreamingMarkdownPresentationTimeline<Int>()
        timeline.applyStreamUpdate(
            update(currentSegment: "tail"),
            commitCurrentSegment: { _, _ in false },
            appendCompletedSegment: { _ in [] },
            removeCurrentRecords: { _ in XCTFail("Should not remove records.") },
            renderCurrentSegment: { _, _ in [3] }
        )

        var removedRecords: [[Int]] = []
        timeline.applyStreamUpdate(
            update(),
            commitCurrentSegment: { _, _ in false },
            appendCompletedSegment: { _ in XCTFail("Should not append completed segment."); return [] },
            removeCurrentRecords: { records in
                removedRecords.append(records)
            },
            renderCurrentSegment: { _, _ in XCTFail("Should not render current segment."); return [] }
        )

        XCTAssertEqual(removedRecords, [[3]])
        XCTAssertNil(timeline.currentSegmentMarkdown)
        XCTAssertTrue(timeline.currentRecords.isEmpty)
        XCTAssertTrue(timeline.completedSegments.isEmpty)
    }

    func testRerenderCompletedSegmentsKeepsMarkdownAndUsesNextRecordStartIndexes() {
        var timeline = ChatStreamingMarkdownPresentationTimeline<Int>()
        timeline.applyStreamUpdate(
            update(completedSegments: ["A", "B"]),
            commitCurrentSegment: { _, _ in false },
            appendCompletedSegment: { markdown in
                markdown == "A" ? [1, 2] : [3]
            },
            removeCurrentRecords: { _ in XCTFail("Should not remove current records.") },
            renderCurrentSegment: { _, _ in XCTFail("Should not render current segment."); return [] }
        )

        var calls: [(markdown: String, records: [Int], startIndex: Int)] = []
        timeline.rerenderCompletedSegments { markdown, records, startIndex in
            calls.append((markdown, records, startIndex))
            return markdown == "A" ? [10] : [20, 21]
        }

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].markdown, "A")
        XCTAssertEqual(calls[0].records, [1, 2])
        XCTAssertEqual(calls[0].startIndex, 0)
        XCTAssertEqual(calls[1].markdown, "B")
        XCTAssertEqual(calls[1].records, [3])
        XCTAssertEqual(calls[1].startIndex, 1)
        XCTAssertEqual(timeline.completedSegments.map(\.markdown), ["A", "B"])
        XCTAssertEqual(timeline.completedSegments.map(\.records), [[10], [20, 21]])
    }

    func testRemoveCurrentRecordsPreservesCurrentMarkdownForRerender() {
        var timeline = ChatStreamingMarkdownPresentationTimeline<Int>()
        timeline.applyStreamUpdate(
            update(currentSegment: "tail"),
            commitCurrentSegment: { _, _ in false },
            appendCompletedSegment: { _ in [] },
            removeCurrentRecords: { _ in XCTFail("Should not remove records.") },
            renderCurrentSegment: { _, _ in [12] }
        )

        var removedRecords: [[Int]] = []
        timeline.removeCurrentRecords { records in
            removedRecords.append(records)
        }

        XCTAssertEqual(removedRecords, [[12]])
        XCTAssertEqual(timeline.currentSegmentMarkdown, "tail")
        XCTAssertTrue(timeline.currentRecords.isEmpty)

        timeline.updateCurrentSegment(markdown: "tail", records: [13])
        XCTAssertEqual(timeline.currentRecords, [13])
    }

    func testSetFinishedMarkdownAndResetReplaceTimelineState() {
        var timeline = ChatStreamingMarkdownPresentationTimeline<Int>()
        timeline.applyStreamUpdate(
            update(currentSegment: "old"),
            commitCurrentSegment: { _, _ in false },
            appendCompletedSegment: { _ in [] },
            removeCurrentRecords: { _ in XCTFail("Should not remove records.") },
            renderCurrentSegment: { _, _ in [1] }
        )

        timeline.setFinishedMarkdown("final") { markdown in
            XCTAssertEqual(markdown, "final")
            return [2]
        }

        XCTAssertEqual(timeline.completedSegments.count, 1)
        XCTAssertEqual(timeline.completedSegments[0].markdown, "final")
        XCTAssertEqual(timeline.completedSegments[0].records, [2])
        XCTAssertNil(timeline.currentSegmentMarkdown)

        timeline.setFinishedMarkdown("") { _ in
            XCTFail("Empty finished markdown should not render records.")
            return [3]
        }

        XCTAssertTrue(timeline.completedSegments.isEmpty)
        XCTAssertNil(timeline.currentSegmentMarkdown)

        timeline.setFinishedMarkdown("again") { _ in [4] }
        timeline.reset()

        XCTAssertTrue(timeline.completedSegments.isEmpty)
        XCTAssertNil(timeline.currentSegmentMarkdown)
        XCTAssertTrue(timeline.currentRecords.isEmpty)
    }

    private func update(
        completedSegments: [String] = [],
        currentSegment: String? = nil
    ) -> ChatMarkdownStreamUpdate {
        ChatMarkdownStreamUpdate(
            completedSegments: completedSegments,
            currentSegment: currentSegment
        )
    }
}
