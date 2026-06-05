//
//  ChatHistoryPresentationWorkflowTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatHistoryPresentationWorkflowTests: XCTestCase {
    func testPresentLoadedSessionClearsPendingAttachmentsWhenPrivateModeIsEnabled() {
        let session = makeTestChatSession(title: "Saved")
        let event = makeTimelineEvent()
        let discardedAttachment = makeAttachment(filename: "discarded.txt")
        let recorder = WorkflowRecorder(
            isPrivacyModeEnabled: true,
            loadDiscardedAttachments: [discardedAttachment]
        )
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentLoadedSession(session, events: [event])

        XCTAssertEqual(
            recorder.events,
            [
                .clearPendingAttachments(deleteFiles: true),
                .loadConversation(sessionID: session.id, eventCount: 1),
                .discardPrivateModeAttachments(["discarded.txt"]),
                .renderConversationTimeline(eventCount: 1),
                .reloadSelectedSystemPrompt,
                .lockMessagesToBottom,
                .updateHeader,
                .confirmPendingSessionSelection(session.id),
                .reloadHistorySessions(selectedSessionID: session.id),
                .closeSideMenu
            ]
        )
    }

    func testPresentLoadedSessionSkipsPendingAttachmentClearingOutsidePrivateMode() {
        let session = makeTestChatSession(title: "Saved")
        let recorder = WorkflowRecorder(isPrivacyModeEnabled: false)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentLoadedSession(session, events: [])

        XCTAssertFalse(recorder.events.contains(.clearPendingAttachments(deleteFiles: true)))
        XCTAssertEqual(recorder.events.first, .loadConversation(sessionID: session.id, eventCount: 0))
    }

    func testDeleteAndResetCurrentDelegatesToSharedResetWorkflow() {
        let recorder = WorkflowRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentDeleteCompletion(.deleteAndResetCurrent)

        XCTAssertEqual(
            recorder.events,
            [
                .resetCurrentConversation
            ]
        )
    }

    func testDeleteOnlyAndIgnoreReloadCurrentSessionWithoutResettingConversation() {
        let currentSessionID = UUID()
        let recorder = WorkflowRecorder(currentSessionID: currentSessionID)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentDeleteCompletion(.deleteOnly)
        workflow.presentDeleteCompletion(.ignore)

        XCTAssertEqual(
            recorder.events,
            [
                .reloadHistorySessions(selectedSessionID: currentSessionID),
                .reloadHistorySessions(selectedSessionID: currentSessionID)
            ]
        )
    }

    private func makeWorkflow(recorder: WorkflowRecorder) -> ChatHistoryPresentationWorkflow {
        ChatHistoryPresentationWorkflow(
            isPrivacyModeEnabled: { recorder.isPrivacyModeEnabled },
            clearPendingAttachments: { deleteFiles in
                recorder.events.append(.clearPendingAttachments(deleteFiles: deleteFiles))
            },
            loadConversation: { session, events in
                recorder.events.append(
                    .loadConversation(sessionID: session.id, eventCount: events.count)
                )
                return recorder.loadDiscardedAttachments
            },
            resetCurrentConversation: {
                recorder.events.append(.resetCurrentConversation)
            },
            discardPrivateModeAttachments: { attachments in
                recorder.events.append(
                    .discardPrivateModeAttachments(attachments.map(\.filename))
                )
            },
            renderConversationTimeline: { events in
                recorder.events.append(.renderConversationTimeline(eventCount: events.count))
            },
            removeChatContent: {
                recorder.events.append(.removeChatContent)
            },
            reloadSelectedSystemPrompt: {
                recorder.events.append(.reloadSelectedSystemPrompt)
            },
            lockMessagesToBottom: {
                recorder.events.append(.lockMessagesToBottom)
            },
            updateHeader: {
                recorder.events.append(.updateHeader)
            },
            confirmPendingSessionSelection: { sessionID in
                recorder.events.append(.confirmPendingSessionSelection(sessionID))
            },
            reloadHistorySessions: { selectedSessionID in
                recorder.events.append(.reloadHistorySessions(selectedSessionID: selectedSessionID))
            },
            closeSideMenu: {
                recorder.events.append(.closeSideMenu)
            },
            currentSessionID: {
                recorder.currentSessionID
            }
        )
    }

    private func makeTimelineEvent() -> ChatTimelineEvent {
        ChatTimelineEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .userMessage(text: "Hello")
        )
    }

    private func makeAttachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            kind: .file,
            filename: filename,
            contentType: "text/plain",
            relativePath: filename
        )
    }
}

@MainActor
private final class WorkflowRecorder {
    var isPrivacyModeEnabled: Bool
    var loadDiscardedAttachments: [ChatAttachment]
    var currentSessionID: UUID
    var events: [WorkflowEvent] = []

    init(
        isPrivacyModeEnabled: Bool = false,
        loadDiscardedAttachments: [ChatAttachment] = [],
        currentSessionID: UUID = UUID()
    ) {
        self.isPrivacyModeEnabled = isPrivacyModeEnabled
        self.loadDiscardedAttachments = loadDiscardedAttachments
        self.currentSessionID = currentSessionID
    }
}

private enum WorkflowEvent: Equatable {
    case clearPendingAttachments(deleteFiles: Bool)
    case loadConversation(sessionID: UUID, eventCount: Int)
    case resetCurrentConversation
    case discardPrivateModeAttachments([String])
    case renderConversationTimeline(eventCount: Int)
    case removeChatContent
    case reloadSelectedSystemPrompt
    case lockMessagesToBottom
    case updateHeader
    case confirmPendingSessionSelection(UUID)
    case reloadHistorySessions(selectedSessionID: UUID?)
    case closeSideMenu
}
