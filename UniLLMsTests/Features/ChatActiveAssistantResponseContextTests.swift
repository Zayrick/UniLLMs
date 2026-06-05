//
//  ChatActiveAssistantResponseContextTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatActiveAssistantResponseContextTests: XCTestCase {
    func testContainsMatchesResponseViewByIdentity() {
        let responseView = ResponseView()
        let otherResponseView = ResponseView()
        let context = makeContext(responseView: responseView)

        XCTAssertTrue(context.contains(responseView: responseView))
        XCTAssertFalse(context.contains(responseView: otherResponseView))
        XCTAssertFalse(context.contains(responseView: nil))
    }

    func testFailureRecoveryPlanRestoresNewMessageBeforeVisibleProgress() {
        let attachment = makeAttachment(filename: "photo.jpg")
        let responseView = ResponseView()
        let context = makeContext(
            presentationState: .newMessage(
                prompt: "Retry this",
                attachments: [attachment]
            ),
            responseView: responseView
        )

        let recoveryPlan = context.failureRecoveryPlan(for: responseView)

        XCTAssertEqual(
            recoveryPlan,
            ChatAssistantResponseFailureRecoveryPlan(
                prompt: "Retry this",
                attachments: [attachment]
            )
        )
    }

    func testContextStoresSentMessageIDWithoutReadingViewType() {
        let messageID = UUID()
        let context = makeContext(sentMessageID: messageID)

        XCTAssertEqual(context.sentMessageID, messageID)
    }

    func testFailureRecoveryPlanIgnoresDifferentResponseView() {
        let context = makeContext(
            presentationState: .newMessage(
                prompt: "Retry this",
                attachments: []
            )
        )

        XCTAssertNil(context.failureRecoveryPlan(for: ResponseView()))
    }

    func testRecordingVisibleProgressDisablesNewMessageRecovery() {
        let responseView = ResponseView()
        let context = makeContext(
            presentationState: .newMessage(
                prompt: "Retry this",
                attachments: []
            ),
            responseView: responseView
        )

        context.recordVisibleProgress(from: ChatResponseDelta(content: "Visible"))

        XCTAssertNil(context.failureRecoveryPlan(for: responseView))
    }

    func testReplacementMessageNeverRestoresDraftAfterFailure() {
        let responseView = ResponseView()
        let context = makeContext(
            presentationState: .replacementMessage(
                prompt: "Edited",
                attachments: []
            ),
            responseView: responseView
        )

        XCTAssertNil(context.failureRecoveryPlan(for: responseView))
    }

    private func makeContext(
        presentationState: ChatResponsePresentationState = .newMessage(
            prompt: "Hello",
            attachments: []
        ),
        sentMessageID: UUID? = nil,
        responseView: ResponseView? = nil
    ) -> ChatActiveAssistantResponseContext<SentMessageView, ResponseView> {
        let responseView = responseView ?? ResponseView()
        return ChatActiveAssistantResponseContext(
            presentationState: presentationState,
            sentMessageID: sentMessageID,
            sentMessageView: SentMessageView(),
            responseView: responseView
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

private final class SentMessageView {}

private final class ResponseView {}
