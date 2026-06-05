//
//  ChatAssistantResponseFailurePresentationWorkflowTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatAssistantResponseFailurePresentationWorkflowTests: XCTestCase {
    func testNewMessageFailureBeforeVisibleProgressRemovesViewsAndRestoresDraft() {
        let viewMessageID = UUID()
        let contextMessageID = UUID()
        let attachment = makeAttachment(filename: "photo.jpg")
        let sentMessageView = SentMessageBubbleView(
            messageID: viewMessageID,
            text: "Retry this",
            attachments: [attachment]
        )
        let responseView = AssistantResponseTextView()
        let context = makeContext(
            sentMessageView: sentMessageView,
            sentMessageID: contextMessageID,
            responseView: responseView,
            presentationState: .newMessage(
                prompt: "Retry this",
                attachments: [attachment]
            )
        )
        let recorder = FailurePresentationRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        let result = workflow.presentFailure(
            message: "Provider failed.",
            responseView: responseView,
            context: context,
            activeResponseView: responseView
        )

        XCTAssertEqual(result, .init(shouldClearActiveResponseView: true))
        XCTAssertEqual(recorder.cancelledMessageIDs, [contextMessageID])
        XCTAssertEqual(recorder.restoredPrompts, ["Retry this"])
        XCTAssertEqual(recorder.restoredAttachments, [[attachment]])
        XCTAssertEqual(recorder.presentedErrors, ["Provider failed."])
        XCTAssertTrue(recorder.removedViews.count == 2)
        XCTAssertTrue(recorder.removedViews[0] === sentMessageView)
        XCTAssertTrue(recorder.removedViews[1] === responseView)
        XCTAssertTrue(recorder.responseErrors.isEmpty)
        XCTAssertEqual(recorder.layoutInvalidationCount, 1)
        XCTAssertEqual(recorder.layoutReconciliationCount, 1)
    }

    func testFailureAfterVisibleProgressKeepsResponseViewAndSetsError() {
        let responseView = AssistantResponseTextView()
        let context = makeContext(responseView: responseView)
        context.recordVisibleProgress(from: ChatResponseDelta(content: "Partial"))
        let recorder = FailurePresentationRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        let result = workflow.presentFailure(
            message: "Provider failed.",
            responseView: responseView,
            context: context,
            activeResponseView: responseView
        )

        XCTAssertEqual(result, .init(shouldClearActiveResponseView: false))
        XCTAssertEqual(recorder.responseErrors.map(\.message), ["Provider failed."])
        XCTAssertTrue(recorder.responseErrors.first?.responseView === responseView)
        XCTAssertTrue(recorder.cancelledMessageIDs.isEmpty)
        XCTAssertTrue(recorder.removedViews.isEmpty)
        XCTAssertTrue(recorder.restoredPrompts.isEmpty)
        XCTAssertTrue(recorder.presentedErrors.isEmpty)
        XCTAssertEqual(recorder.layoutInvalidationCount, 0)
        XCTAssertEqual(recorder.layoutReconciliationCount, 0)
    }

    func testRecoveredFailureDoesNotClearDifferentActiveResponseView() {
        let responseView = AssistantResponseTextView()
        let activeResponseView = AssistantResponseTextView()
        let context = makeContext(responseView: responseView)
        let recorder = FailurePresentationRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        let result = workflow.presentFailure(
            message: "Provider failed.",
            responseView: responseView,
            context: context,
            activeResponseView: activeResponseView
        )

        XCTAssertEqual(result, .init(shouldClearActiveResponseView: false))
        XCTAssertEqual(recorder.presentedErrors, ["Provider failed."])
        XCTAssertTrue(recorder.responseErrors.isEmpty)
    }

    private func makeContext(
        sentMessageView: SentMessageBubbleView? = nil,
        sentMessageID: UUID? = nil,
        responseView: AssistantResponseTextView,
        presentationState: ChatResponsePresentationState = .newMessage(
            prompt: "Hello",
            attachments: []
        )
    ) -> ChatAssistantResponseFailurePresentationWorkflow.ActiveContext {
        let sentMessageView = sentMessageView ?? SentMessageBubbleView(text: "Hello")
        return ChatActiveAssistantResponseContext(
            presentationState: presentationState,
            sentMessageID: sentMessageID ?? sentMessageView.messageID,
            sentMessageView: sentMessageView,
            responseView: responseView
        )
    }

    private func makeWorkflow(
        recorder: FailurePresentationRecorder
    ) -> ChatAssistantResponseFailurePresentationWorkflow {
        ChatAssistantResponseFailurePresentationWorkflow(
            cancelMessageAttachmentDisplays: { recorder.cancelledMessageIDs.append($0) },
            removeViews: { recorder.removedViews.append(contentsOf: $0) },
            restoreComposerDraft: { prompt, attachments in
                recorder.restoredPrompts.append(prompt)
                recorder.restoredAttachments.append(attachments)
            },
            presentError: { recorder.presentedErrors.append($0) },
            setResponseError: { message, responseView in
                recorder.responseErrors.append((message, responseView))
            },
            invalidateRemovedViewsLayout: { recorder.layoutInvalidationCount += 1 },
            reconcileAfterRemovedViews: { recorder.layoutReconciliationCount += 1 }
        )
    }

    private func makeAttachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .image,
            filename: filename,
            contentType: "image/jpeg",
            relativePath: "attachments/\(filename)"
        )
    }
}

@MainActor
private final class FailurePresentationRecorder {
    var cancelledMessageIDs: [UUID] = []
    var removedViews: [UIView] = []
    var restoredPrompts: [String] = []
    var restoredAttachments: [[ChatAttachment]] = []
    var presentedErrors: [String] = []
    var responseErrors: [(message: String, responseView: AssistantResponseTextView)] = []
    var layoutInvalidationCount = 0
    var layoutReconciliationCount = 0
}
