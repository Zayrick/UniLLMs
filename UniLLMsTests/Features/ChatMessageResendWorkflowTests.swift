//
//  ChatMessageResendWorkflowTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatMessageResendWorkflowTests: XCTestCase {
    func testResendEditedMessageTrimsTextBeforePreparingReplacementTurn() {
        let messageID = UUID()
        let recorder = ResendWorkflowRecorder(firstRemovedIndex: 4)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.resendEditedMessage(
            messageID: messageID,
            text: "\n  Edited  \n",
            attachments: []
        )

        XCTAssertEqual(
            recorder.events,
            [
                .layoutIfNeeded,
                .captureExistingMessagesSnapshot,
                .prepare(prompt: "Edited", firstRemovedIndex: 4),
                .perform(prompt: "Edited")
            ]
        )
    }

    func testEmptyResendWithoutAttachmentsIsIgnored() {
        let recorder = ResendWorkflowRecorder(firstRemovedIndex: 2)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.resendMessage(messageID: UUID(), text: "", attachments: [])

        XCTAssertEqual(recorder.events, [])
    }

    func testActiveResponseFailsWithoutPreparingTurn() {
        let recorder = ResendWorkflowRecorder(
            isResponseActive: true,
            firstRemovedIndex: 2
        )
        let workflow = makeWorkflow(recorder: recorder)

        workflow.resendMessage(messageID: UUID(), text: "Retry", attachments: [])

        XCTAssertEqual(recorder.events, [.presentActionFailure(.responseInProgress)])
        XCTAssertEqual(recorder.firstRemovedIndexCallCount, 0)
    }

    func testMissingMessageFailsWithoutPreparingTurn() {
        let recorder = ResendWorkflowRecorder(firstRemovedIndex: nil)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.resendMessage(messageID: UUID(), text: "Retry", attachments: [])

        XCTAssertEqual(recorder.events, [.presentActionFailure(.messageUnavailable)])
    }

    func testPrepareFailurePresentsErrorWithoutPerformingTransaction() {
        let recorder = ResendWorkflowRecorder(
            firstRemovedIndex: 1,
            prepareError: ResendWorkflowFailure.sample
        )
        let workflow = makeWorkflow(recorder: recorder)

        workflow.resendMessage(messageID: UUID(), text: "Retry", attachments: [])

        XCTAssertEqual(
            recorder.events,
            [
                .layoutIfNeeded,
                .captureExistingMessagesSnapshot,
                .prepare(prompt: "Retry", firstRemovedIndex: 1),
                .presentError("Unable to resend.")
            ]
        )
    }

    func testAttachmentOnlyResendPreparesReplacementTurn() {
        let attachment = ChatAttachment(
            kind: .file,
            filename: "notes.txt",
            contentType: "text/plain",
            relativePath: "notes.txt"
        )
        let recorder = ResendWorkflowRecorder(firstRemovedIndex: 3)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.resendMessage(messageID: UUID(), text: "", attachments: [attachment])

        XCTAssertEqual(
            recorder.events,
            [
                .layoutIfNeeded,
                .captureExistingMessagesSnapshot,
                .prepare(prompt: "", firstRemovedIndex: 3),
                .perform(prompt: "")
            ]
        )
    }

    private func makeWorkflow(recorder: ResendWorkflowRecorder) -> ChatMessageResendWorkflow {
        ChatMessageResendWorkflow(
            isResponseActive: { recorder.isResponseActive },
            firstRemovedIndex: { _ in
                recorder.firstRemovedIndexCallCount += 1
                return recorder.firstRemovedIndex
            },
            layoutIfNeeded: {
                recorder.events.append(.layoutIfNeeded)
            },
            captureExistingMessagesSnapshot: {
                recorder.events.append(.captureExistingMessagesSnapshot)
                return .empty
            },
            prepareOutgoingTurn: { transactionPlan in
                recorder.events.append(
                    .prepare(
                        prompt: transactionPlan.prompt,
                        firstRemovedIndex: transactionPlan.firstRemovedIndex ?? -1
                    )
                )
                if let prepareError = recorder.prepareError {
                    throw prepareError
                }
                return ChatPreparedOutgoingTurn(
                    transactionPlan: transactionPlan,
                    preparedStream: ChatPreparedAssistantResponseStream(
                        responseStream: AsyncThrowingStream { continuation in
                            continuation.finish()
                        },
                        continuationTask: nil
                    )
                )
            },
            performTransaction: { transactionPlan, _, _ in
                recorder.events.append(.perform(prompt: transactionPlan.prompt))
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
private final class ResendWorkflowRecorder {
    var isResponseActive: Bool
    var firstRemovedIndex: Int?
    var firstRemovedIndexCallCount = 0
    var prepareError: Error?
    var events: [ResendWorkflowEvent] = []

    init(
        isResponseActive: Bool = false,
        firstRemovedIndex: Int?,
        prepareError: Error? = nil
    ) {
        self.isResponseActive = isResponseActive
        self.firstRemovedIndex = firstRemovedIndex
        self.prepareError = prepareError
    }
}

private enum ResendWorkflowEvent: Equatable {
    case layoutIfNeeded
    case captureExistingMessagesSnapshot
    case prepare(prompt: String, firstRemovedIndex: Int)
    case perform(prompt: String)
    case presentActionFailure(ChatMessageActionPolicy.FailureReason)
    case presentError(String)
}

private enum ResendWorkflowFailure: LocalizedError {
    case sample

    var errorDescription: String? {
        "Unable to resend."
    }
}
