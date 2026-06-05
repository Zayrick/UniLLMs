//
//  SentMessageBubbleActionRouterTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class SentMessageBubbleActionRouterTests: XCTestCase {
    func testCopyRunsImmediatelyWithoutWaitingForDismissal() {
        let recorder = SentMessageBubbleActionRouterRecorder()
        let router = makeRouter(
            messageText: "Hello",
            attachments: [],
            recorder: recorder
        )

        router.perform(.copy)

        XCTAssertEqual(recorder.events, [.copyText("Hello")])
        XCTAssertNil(recorder.deferredAction)
    }

    func testResendRunsAfterDismissalWithMessagePayload() throws {
        let attachment = makeAttachment()
        let recorder = SentMessageBubbleActionRouterRecorder()
        let router = makeRouter(
            messageText: "Retry",
            attachments: [attachment],
            recorder: recorder
        )

        router.perform(.resend)

        XCTAssertEqual(recorder.events, [.performAfterDismissal])

        let deferredAction = try XCTUnwrap(recorder.deferredAction)
        deferredAction()

        XCTAssertEqual(
            recorder.events,
            [
                .performAfterDismissal,
                .resend(text: "Retry", attachments: [attachment])
            ]
        )
    }

    func testEditAndResendRunsAfterDismissalWithMessagePayload() throws {
        let attachment = makeAttachment()
        let recorder = SentMessageBubbleActionRouterRecorder()
        let router = makeRouter(
            messageText: "Draft",
            attachments: [attachment],
            recorder: recorder
        )

        router.perform(.editAndResend)

        let deferredAction = try XCTUnwrap(recorder.deferredAction)
        deferredAction()

        XCTAssertEqual(
            recorder.events,
            [
                .performAfterDismissal,
                .editAndResend(text: "Draft", attachments: [attachment])
            ]
        )
    }

    func testShowHistoryRunsAfterDismissal() throws {
        let recorder = SentMessageBubbleActionRouterRecorder()
        let router = makeRouter(
            messageText: "Draft",
            attachments: [],
            recorder: recorder
        )

        router.perform(.showHistory)

        let deferredAction = try XCTUnwrap(recorder.deferredAction)
        deferredAction()

        XCTAssertEqual(recorder.events, [.performAfterDismissal, .showHistory])
    }

    private func makeRouter(
        messageText: String,
        attachments: [ChatAttachment],
        recorder: SentMessageBubbleActionRouterRecorder
    ) -> SentMessageBubbleActionRouter {
        SentMessageBubbleActionRouter(
            messageText: messageText,
            attachments: attachments,
            copyText: { text in
                recorder.events.append(.copyText(text))
            },
            performAfterDismissal: { action in
                recorder.events.append(.performAfterDismissal)
                recorder.deferredAction = action
            },
            resend: { text, attachments in
                recorder.events.append(.resend(text: text, attachments: attachments))
            },
            editAndResend: { text, attachments in
                recorder.events.append(.editAndResend(text: text, attachments: attachments))
            },
            showHistory: {
                recorder.events.append(.showHistory)
            }
        )
    }

    private func makeAttachment() -> ChatAttachment {
        ChatAttachment(
            kind: .file,
            filename: "notes.txt",
            contentType: "text/plain",
            relativePath: "notes.txt"
        )
    }
}

@MainActor
private final class SentMessageBubbleActionRouterRecorder {
    var events: [SentMessageBubbleActionRouterEvent] = []
    var deferredAction: (() -> Void)?
}

private enum SentMessageBubbleActionRouterEvent: Equatable {
    case copyText(String)
    case performAfterDismissal
    case resend(text: String, attachments: [ChatAttachment])
    case editAndResend(text: String, attachments: [ChatAttachment])
    case showHistory
}
