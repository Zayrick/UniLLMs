//
//  ChatMessageActionPresentationWorkflowTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatMessageActionPresentationWorkflowTests: XCTestCase {
    func testEditorPresentationFailsDuringActiveResponseWithoutPresenting() {
        let recorder = MessageActionPresentationRecorder(isResponseActive: true)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentEditor(messageID: UUID(), text: "Draft", attachments: [])

        XCTAssertEqual(recorder.events, [.presentActionFailure(.responseInProgress)])
        XCTAssertEqual(recorder.containsMessageCallCount, 0)
        XCTAssertNil(recorder.presentedViewController)
    }

    func testEditorPresentationIgnoresWhenModalIsAlreadyPresented() {
        let recorder = MessageActionPresentationRecorder(isPresentingModal: true)
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentEditor(messageID: UUID(), text: "Draft", attachments: [])

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(recorder.containsMessageCallCount, 0)
        XCTAssertNil(recorder.presentedViewController)
    }

    func testEditorPresentationBuildsAndRoutesSubmit() throws {
        let messageID = UUID()
        let attachment = makeAttachment()
        let recorder = MessageActionPresentationRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentEditor(messageID: messageID, text: "Draft", attachments: [attachment])

        XCTAssertEqual(
            recorder.events,
            [
                .endEditing,
                .makeEditor(text: "Draft", attachments: [attachment]),
                .presentViewController
            ]
        )
        XCTAssertTrue(recorder.presentedViewController === recorder.editorViewController)

        let onSubmit = try XCTUnwrap(recorder.editorSubmit)
        onSubmit("Edited")

        XCTAssertEqual(
            recorder.events.suffix(1),
            [.resendEditedMessage(messageID: messageID, text: "Edited", attachments: [attachment])]
        )
    }

    func testRevisionHistoryFailsWhenMessageIsUnavailable() {
        let recorder = MessageActionPresentationRecorder(containsMessage: false)
        recorder.revisions = [makeRevision()]
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentRevisionHistory(messageID: UUID())

        XCTAssertEqual(recorder.events, [.presentActionFailure(.messageUnavailable)])
        XCTAssertEqual(recorder.messageRevisionsCallCount, 0)
        XCTAssertNil(recorder.presentedViewController)
    }

    func testRevisionHistoryIgnoresWhenNoRevisionsExist() {
        let recorder = MessageActionPresentationRecorder()
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentRevisionHistory(messageID: UUID())

        XCTAssertEqual(recorder.events, [])
        XCTAssertNil(recorder.presentedViewController)
    }

    func testRevisionHistoryPresentationBuildsAndRoutesSelection() throws {
        let messageID = UUID()
        let revision = makeRevision(anchorUserMessageID: messageID)
        let recorder = MessageActionPresentationRecorder()
        recorder.revisions = [revision]
        let workflow = makeWorkflow(recorder: recorder)

        workflow.presentRevisionHistory(messageID: messageID)

        XCTAssertEqual(
            recorder.events,
            [
                .endEditing,
                .makeRevisionHistory(revisionIDs: [revision.id]),
                .presentViewController
            ]
        )
        XCTAssertTrue(recorder.presentedViewController === recorder.historyViewController)

        let onSelectRevision = try XCTUnwrap(recorder.revisionSelection)
        onSelectRevision(revision)

        XCTAssertEqual(
            recorder.events.suffix(1),
            [.switchToMessageRevision(messageID: messageID, revisionID: revision.id)]
        )
    }

    private func makeWorkflow(
        recorder: MessageActionPresentationRecorder
    ) -> ChatMessageActionPresentationWorkflow {
        ChatMessageActionPresentationWorkflow(
            isResponseActive: {
                recorder.isResponseActive
            },
            isPresentingModal: {
                recorder.isPresentingModal
            },
            containsMessage: { _ in
                recorder.containsMessageCallCount += 1
                return recorder.containsMessage
            },
            messageRevisions: { _ in
                recorder.messageRevisionsCallCount += 1
                return recorder.revisions
            },
            endEditing: {
                recorder.events.append(.endEditing)
            },
            makeEditor: { text, attachments, onSubmit in
                recorder.events.append(.makeEditor(text: text, attachments: attachments))
                recorder.editorSubmit = onSubmit
                return recorder.editorViewController
            },
            makeRevisionHistory: { revisions, onSelectRevision in
                recorder.events.append(.makeRevisionHistory(revisionIDs: revisions.map(\.id)))
                recorder.revisionSelection = onSelectRevision
                return recorder.historyViewController
            },
            presentViewController: { viewController in
                recorder.events.append(.presentViewController)
                recorder.presentedViewController = viewController
            },
            presentActionFailure: { reason in
                recorder.events.append(.presentActionFailure(reason))
            },
            resendEditedMessage: { messageID, text, attachments in
                recorder.events.append(
                    .resendEditedMessage(
                        messageID: messageID,
                        text: text,
                        attachments: attachments
                    )
                )
            },
            switchToMessageRevision: { messageID, revisionID in
                recorder.events.append(
                    .switchToMessageRevision(
                        messageID: messageID,
                        revisionID: revisionID
                    )
                )
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

    private func makeRevision(
        anchorUserMessageID: UUID = UUID()
    ) -> ChatMessageRevision {
        ChatMessageRevision(
            id: UUID(),
            anchorUserMessageID: anchorUserMessageID,
            archivedAt: Date(timeIntervalSince1970: 1),
            events: [
                ChatTimelineEvent(
                    timestamp: Date(timeIntervalSince1970: 1),
                    kind: .userMessage(text: "Earlier")
                )
            ]
        )
    }
}

@MainActor
private final class MessageActionPresentationRecorder {
    var isResponseActive: Bool
    var isPresentingModal: Bool
    var containsMessage: Bool
    var containsMessageCallCount = 0
    var messageRevisionsCallCount = 0
    var revisions: [ChatMessageRevision] = []
    let editorViewController = UIViewController()
    let historyViewController = UIViewController()
    var editorSubmit: ((String) -> Void)?
    var revisionSelection: ((ChatMessageRevision) -> Void)?
    weak var presentedViewController: UIViewController?
    var events: [MessageActionPresentationEvent] = []

    init(
        isResponseActive: Bool = false,
        isPresentingModal: Bool = false,
        containsMessage: Bool = true
    ) {
        self.isResponseActive = isResponseActive
        self.isPresentingModal = isPresentingModal
        self.containsMessage = containsMessage
    }
}

private enum MessageActionPresentationEvent: Equatable {
    case endEditing
    case makeEditor(text: String, attachments: [ChatAttachment])
    case makeRevisionHistory(revisionIDs: [UUID])
    case presentViewController
    case presentActionFailure(ChatMessageActionPolicy.FailureReason)
    case resendEditedMessage(messageID: UUID, text: String, attachments: [ChatAttachment])
    case switchToMessageRevision(messageID: UUID, revisionID: UUID)
}
