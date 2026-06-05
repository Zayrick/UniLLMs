//
//  ChatTurnProgressTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatTurnProgressTests: XCTestCase {
    func testEmptyProgressHasNoPersistableEvents() {
        let progress = ChatTurnProgress()

        XCTAssertFalse(progress.hasPersistableProgress)
        XCTAssertTrue(progress.finishedEvents().isEmpty)
    }

    func testDisplayDeltaAccumulatesVisibleTextEvents() {
        let timestamp = Date(timeIntervalSince1970: 10)
        var progress = ChatTurnProgress(clock: FixedClock(now: timestamp))

        progress.append(
            displayDelta: ChatResponseDelta(reasoning: "Thinking ")
        )
        progress.append(
            displayDelta: ChatResponseDelta(content: "Answer")
        )

        XCTAssertTrue(progress.hasPersistableProgress)
        XCTAssertEqual(progress.finishedEvents().map(\.kind), [
            .assistantReasoning(text: "Thinking "),
            .assistantContent(markdown: "Answer")
        ])
        XCTAssertEqual(progress.finishedEvents().map(\.timestamp), [timestamp, timestamp])
    }

    func testDisplayToolEventsDoNotCreatePersistableProgressByThemselves() {
        var progress = ChatTurnProgress(clock: FixedClock(now: Date(timeIntervalSince1970: 10)))
        let toolCall = ChatToolCall(id: "call_1", toolID: "search")

        progress.append(
            displayDelta: ChatResponseDelta(
                displayParts: [.toolEvent(.started(toolCall))]
            )
        )

        XCTAssertFalse(progress.hasPersistableProgress)
        XCTAssertTrue(progress.finishedEvents().isEmpty)
    }

    func testTimelineEventsCreatePersistableProgress() {
        let timestamp = Date(timeIntervalSince1970: 10)
        var progress = ChatTurnProgress(clock: FixedClock(now: timestamp))
        let toolCall = ChatToolCall(id: "call_1", toolID: "search")

        progress.append(
            timelineEvent: .assistantToolCalls([toolCall])
        )

        XCTAssertTrue(progress.hasPersistableProgress)
        XCTAssertEqual(progress.finishedEvents().map(\.kind), [
            .assistantToolCalls([toolCall])
        ])
        XCTAssertEqual(progress.finishedEvents().map(\.timestamp), [timestamp])
    }
}

private struct FixedClock: AppClock {
    var now: Date
}
