//
//  ChatTurnProgress.swift
//  UniLLMs
//
//  Accumulates the persistable timeline events produced during one chat turn.
//

import Foundation

nonisolated struct ChatTurnProgress: Equatable {
    private var timelineAccumulator = ChatTimelineAccumulator()
    private let clock: any AppClock

    init(
        clock: any AppClock = SystemAppClock(),
        events: [ChatTimelineEvent] = []
    ) {
        self.clock = clock
        timelineAccumulator = ChatTimelineAccumulator(events: events)
    }

    var hasPersistableProgress: Bool {
        !timelineAccumulator.events.isEmpty
    }

    mutating func append(displayDelta delta: ChatResponseDelta) {
        timelineAccumulator.appendDisplayDelta(delta, timestamp: clock.now)
    }

    mutating func append(timelineEvent kind: ChatTimelineEvent.Kind) {
        timelineAccumulator.append(
            ChatTimelineEvent(
                timestamp: clock.now,
                kind: kind
            )
        )
    }

    func finishedEvents() -> [ChatTimelineEvent] {
        timelineAccumulator.events
    }

    static func == (lhs: ChatTurnProgress, rhs: ChatTurnProgress) -> Bool {
        lhs.timelineAccumulator == rhs.timelineAccumulator
    }
}
