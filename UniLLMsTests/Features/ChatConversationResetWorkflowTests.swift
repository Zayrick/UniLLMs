//
//  ChatConversationResetWorkflowTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatConversationResetWorkflowTests: XCTestCase {
    func testStartNewConversationInPrivateModeClearsPendingAttachmentsAndKeepsPrivacyMode() {
        let discardedAttachment = makeAttachment(filename: "private.txt")
        let recorder = ResetWorkflowRecorder(discardedAttachments: [discardedAttachment])
        let workflow = makeWorkflow(recorder: recorder)

        workflow.perform(.startNewConversation(isPrivacyModeEnabled: true))

        XCTAssertEqual(
            recorder.events,
            [
                .clearPendingAttachments(deleteFiles: true),
                .resetConversation(privacyMode: true),
                .discardPrivateModeAttachments(["private.txt"]),
                .removeChatContent,
                .reloadSelectedSystemPrompt,
                .lockMessagesToBottom,
                .updateHeader,
                .reloadHistorySessions(selectedSessionID: nil)
            ]
        )
    }

    func testStartNewConversationOutsidePrivateModeSkipsPendingAttachmentClearing() {
        let recorder = ResetWorkflowRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        workflow.perform(.startNewConversation(isPrivacyModeEnabled: false))

        XCTAssertFalse(recorder.events.contains(.clearPendingAttachments(deleteFiles: true)))
        XCTAssertEqual(recorder.events.first, .resetConversation(privacyMode: false))
    }

    func testTogglePrivacyModeClearsPendingAttachmentsAndFlipsPrivacyMode() {
        let recorder = ResetWorkflowRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        workflow.perform(.togglePrivacyMode(isPrivacyModeEnabled: false))
        workflow.perform(.togglePrivacyMode(isPrivacyModeEnabled: true))

        XCTAssertEqual(
            recorder.events.prefix(2),
            [
                .clearPendingAttachments(deleteFiles: true),
                .resetConversation(privacyMode: true)
            ]
        )
        XCTAssertEqual(
            Array(recorder.events.dropFirst(8).prefix(2)),
            [
                .clearPendingAttachments(deleteFiles: true),
                .resetConversation(privacyMode: false)
            ]
        )
    }

    func testDeleteCurrentHistorySessionUsesDefaultRuntimeResetAndSharedPresentationRefresh() {
        let recorder = ResetWorkflowRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        workflow.perform(.deleteCurrentHistorySession)

        XCTAssertEqual(
            recorder.events,
            [
                .resetConversation(privacyMode: nil),
                .discardPrivateModeAttachments([]),
                .removeChatContent,
                .reloadSelectedSystemPrompt,
                .lockMessagesToBottom,
                .updateHeader,
                .reloadHistorySessions(selectedSessionID: nil)
            ]
        )
    }

    private func makeWorkflow(recorder: ResetWorkflowRecorder) -> ChatConversationResetWorkflow {
        ChatConversationResetWorkflow(
            clearPendingAttachments: { deleteFiles in
                recorder.events.append(.clearPendingAttachments(deleteFiles: deleteFiles))
            },
            resetConversation: { privacyMode in
                recorder.events.append(.resetConversation(privacyMode: privacyMode))
                return recorder.discardedAttachments
            },
            discardPrivateModeAttachments: { attachments in
                recorder.events.append(
                    .discardPrivateModeAttachments(attachments.map(\.filename))
                )
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
            reloadHistorySessions: { selectedSessionID in
                recorder.events.append(.reloadHistorySessions(selectedSessionID: selectedSessionID))
            }
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
private final class ResetWorkflowRecorder {
    var discardedAttachments: [ChatAttachment]
    var events: [ResetWorkflowEvent] = []

    init(discardedAttachments: [ChatAttachment] = []) {
        self.discardedAttachments = discardedAttachments
    }
}

private enum ResetWorkflowEvent: Equatable {
    case clearPendingAttachments(deleteFiles: Bool)
    case resetConversation(privacyMode: Bool?)
    case discardPrivateModeAttachments([String])
    case removeChatContent
    case reloadSelectedSystemPrompt
    case lockMessagesToBottom
    case updateHeader
    case reloadHistorySessions(selectedSessionID: UUID?)
}
