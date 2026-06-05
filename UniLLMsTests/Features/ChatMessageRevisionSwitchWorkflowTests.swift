//
//  ChatMessageRevisionSwitchWorkflowTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatMessageRevisionSwitchWorkflowTests: XCTestCase {
    func testActiveResponseFailsWithoutSwitchingRevision() {
        let recorder = RevisionSwitchRecorder(isResponseActive: true)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.switchRevision(messageID: UUID(), revisionID: UUID())

        XCTAssertEqual(
            recorder.events,
            [
                .presentActionFailure(.responseInProgress)
            ]
        )
    }

    func testSuccessfulRevisionSwitchRendersAndRefreshesInOrder() {
        let messageID = UUID()
        let revisionID = UUID()
        let currentSessionID = UUID()
        let event = ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "Restored")
        )
        let recorder = RevisionSwitchRecorder(
            currentSessionID: currentSessionID,
            switchedEvents: [event]
        )
        let workflow = makeWorkflow(recorder: recorder)

        workflow.switchRevision(messageID: messageID, revisionID: revisionID)

        XCTAssertEqual(
            recorder.events,
            [
                .switchRevision(messageID: messageID, revisionID: revisionID),
                .renderConversationTimeline(eventCount: 1),
                .lockMessagesToBottom,
                .updateHeader,
                .reloadHistorySessions(selectedSessionID: currentSessionID)
            ]
        )
    }

    func testRevisionSwitchFailurePresentsErrorWithoutRefreshingTimeline() {
        let recorder = RevisionSwitchRecorder(switchError: RevisionSwitchFailure.sample)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.switchRevision(messageID: UUID(), revisionID: UUID())

        XCTAssertEqual(
            recorder.events,
            [
                .switchRevision(messageID: recorder.lastMessageID, revisionID: recorder.lastRevisionID),
                .presentError("Revision unavailable.")
            ]
        )
    }

    private func makeWorkflow(
        recorder: RevisionSwitchRecorder
    ) -> ChatMessageRevisionSwitchWorkflow {
        ChatMessageRevisionSwitchWorkflow(
            isResponseActive: { recorder.isResponseActive },
            switchToMessageRevision: { messageID, revisionID in
                recorder.lastMessageID = messageID
                recorder.lastRevisionID = revisionID
                recorder.events.append(.switchRevision(messageID: messageID, revisionID: revisionID))
                if let switchError = recorder.switchError {
                    throw switchError
                }
                return recorder.switchedEvents
            },
            renderConversationTimeline: { events in
                recorder.events.append(.renderConversationTimeline(eventCount: events.count))
            },
            lockMessagesToBottom: {
                recorder.events.append(.lockMessagesToBottom)
            },
            updateHeader: {
                recorder.events.append(.updateHeader)
            },
            reloadHistorySessions: { selectedSessionID in
                recorder.events.append(.reloadHistorySessions(selectedSessionID: selectedSessionID))
            },
            currentSessionID: {
                recorder.currentSessionID
            },
            presentActionFailure: { reason in
                recorder.events.append(.presentActionFailure(reason))
            },
            presentError: { message in
                recorder.events.append(.presentError(message))
            }
        )
    }
}

@MainActor
private final class RevisionSwitchRecorder {
    var isResponseActive: Bool
    var currentSessionID: UUID
    var switchedEvents: [ChatTimelineEvent]
    var switchError: Error?
    var lastMessageID = UUID()
    var lastRevisionID = UUID()
    var events: [RevisionSwitchEvent] = []

    init(
        isResponseActive: Bool = false,
        currentSessionID: UUID = UUID(),
        switchedEvents: [ChatTimelineEvent] = [],
        switchError: Error? = nil
    ) {
        self.isResponseActive = isResponseActive
        self.currentSessionID = currentSessionID
        self.switchedEvents = switchedEvents
        self.switchError = switchError
    }
}

private enum RevisionSwitchEvent: Equatable {
    case switchRevision(messageID: UUID, revisionID: UUID)
    case renderConversationTimeline(eventCount: Int)
    case lockMessagesToBottom
    case updateHeader
    case reloadHistorySessions(selectedSessionID: UUID?)
    case presentActionFailure(ChatMessageActionPolicy.FailureReason)
    case presentError(String)
}

private enum RevisionSwitchFailure: LocalizedError {
    case sample

    var errorDescription: String? {
        "Revision unavailable."
    }
}
