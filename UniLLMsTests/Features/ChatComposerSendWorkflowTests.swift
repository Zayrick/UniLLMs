//
//  ChatComposerSendWorkflowTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatComposerSendWorkflowTests: XCTestCase {
    func testSendFailsDuringActiveResponseWithoutPreparingOrPerforming() {
        let recorder = ComposerSendWorkflowRecorder(isResponseActive: true)
        let workflow = makeWorkflow(recorder: recorder)

        let didSend = workflow.send(makeTransition(text: "Hello"))

        XCTAssertFalse(didSend)
        XCTAssertEqual(recorder.events, [.presentError(String(localized: .chatResponseInProgress))])
    }

    func testSendPreparesAndPerformsTransactionInOrder() {
        let recorder = ComposerSendWorkflowRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        let didSend = workflow.send(makeTransition(text: "Hello"))

        XCTAssertTrue(didSend)
        XCTAssertEqual(
            recorder.events,
            [
                .layoutIfNeeded,
                .captureExistingMessagesSnapshot,
                .prepareNewMessage("Hello"),
                .performTransaction(preparedPrompt: "Hello", transitionText: "Hello")
            ]
        )
    }

    func testSendPrepareFailurePresentsErrorAndUpdatesHeaderWithoutPerforming() {
        let recorder = ComposerSendWorkflowRecorder(prepareError: ComposerSendFailure.sample)
        let workflow = makeWorkflow(recorder: recorder)

        let didSend = workflow.send(makeTransition(text: "Hello"))

        XCTAssertFalse(didSend)
        XCTAssertEqual(
            recorder.events,
            [
                .layoutIfNeeded,
                .captureExistingMessagesSnapshot,
                .prepareNewMessage("Hello"),
                .presentError("Unable to send."),
                .updateHeaderAfterPrepareFailure
            ]
        )
    }

    private func makeWorkflow(
        recorder: ComposerSendWorkflowRecorder
    ) -> ChatComposerSendWorkflow {
        ChatComposerSendWorkflow(
            isResponseActive: {
                recorder.isResponseActive
            },
            layoutIfNeeded: {
                recorder.events.append(.layoutIfNeeded)
            },
            captureExistingMessagesSnapshot: {
                recorder.events.append(.captureExistingMessagesSnapshot)
                return .empty
            },
            prepareNewMessage: { text in
                recorder.events.append(.prepareNewMessage(text))
                if let prepareError = recorder.prepareError {
                    throw prepareError
                }
                let transactionPlan = ChatOutgoingMessageTransactionPlan.newMessage(
                    text: text,
                    attachments: []
                )
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
            performTransaction: { preparedTurn, _, transition in
                recorder.events.append(
                    .performTransaction(
                        preparedPrompt: preparedTurn.transactionPlan.prompt,
                        transitionText: transition.text
                    )
                )
            },
            presentError: { message in
                recorder.events.append(.presentError(message))
            },
            updateHeaderAfterPrepareFailure: {
                recorder.events.append(.updateHeaderAfterPrepareFailure)
            }
        )
    }

    private func makeTransition(text: String) -> ChatComposerSendTransition {
        ChatComposerSendTransition(
            text: text,
            backgroundGlobalFrame: .zero
        )
    }
}

@MainActor
private final class ComposerSendWorkflowRecorder {
    var isResponseActive: Bool
    var prepareError: Error?
    var events: [ComposerSendWorkflowEvent] = []

    init(
        isResponseActive: Bool = false,
        prepareError: Error? = nil
    ) {
        self.isResponseActive = isResponseActive
        self.prepareError = prepareError
    }
}

private enum ComposerSendWorkflowEvent: Equatable {
    case layoutIfNeeded
    case captureExistingMessagesSnapshot
    case prepareNewMessage(String)
    case performTransaction(preparedPrompt: String, transitionText: String)
    case presentError(String)
    case updateHeaderAfterPrepareFailure
}

private enum ComposerSendFailure: LocalizedError {
    case sample

    var errorDescription: String? {
        "Unable to send."
    }
}
