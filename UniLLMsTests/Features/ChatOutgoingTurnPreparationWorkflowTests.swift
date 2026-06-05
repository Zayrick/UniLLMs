//
//  ChatOutgoingTurnPreparationWorkflowTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatOutgoingTurnPreparationWorkflowTests: XCTestCase {
    func testPrepareNewMessageStartsTurnThenConsumesComposerAttachments() throws {
        let events = EventLog()
        let turnStarter = RecordingTurnStarter(events: events)
        let continuationPolicy = RecordingContinuationTaskPolicy()
        let composerConsumer = RecordingComposerAttachmentConsumer(events: events)
        let attachment = makeAttachment()
        composerConsumer.stagedAttachments = [attachment]
        let workflow = ChatOutgoingTurnPreparationWorkflow(
            turnStarter: turnStarter,
            continuationTaskPolicy: continuationPolicy,
            composerAttachmentStaging: composerConsumer
        )
        let messageID = UUID()

        let preparedTurn = try workflow.prepareNewMessage(
            text: "Hello",
            messageID: messageID
        )

        XCTAssertEqual(
            preparedTurn.transactionPlan,
            ChatOutgoingMessageTransactionPlan.newMessage(
                text: "Hello",
                attachments: [attachment],
                messageID: messageID
            )
        )
        XCTAssertNil(preparedTurn.preparedStream.continuationTask)
        XCTAssertEqual(continuationPolicy.beginCount, 1)
        XCTAssertEqual(composerConsumer.pendingAttachmentsSnapshotCount, 1)
        XCTAssertEqual(turnStarter.startRequests, [
            RecordingTurnStarter.Request(
                prompt: "Hello",
                attachments: [attachment],
                userMessageID: messageID,
                replacingUserMessageID: nil
            )
        ])
        XCTAssertEqual(composerConsumer.consumeCount, 1)
        XCTAssertTrue(composerConsumer.stagedAttachments.isEmpty)
        XCTAssertEqual(events.values, ["startTurn", "consume"])
    }

    func testPrepareReplacementStartsTurnWithoutConsumingComposerAttachments() throws {
        let events = EventLog()
        let turnStarter = RecordingTurnStarter(events: events)
        let continuationTask = ChatContinuationTask()
        let continuationPolicy = RecordingContinuationTaskPolicy(task: continuationTask)
        let composerConsumer = RecordingComposerAttachmentConsumer(events: events)
        let workflow = ChatOutgoingTurnPreparationWorkflow(
            turnStarter: turnStarter,
            continuationTaskPolicy: continuationPolicy,
            composerAttachmentStaging: composerConsumer
        )
        let messageID = UUID()
        let attachment = makeAttachment()
        let resendPlan = ChatMessageResendPlan(
            messageID: messageID,
            text: "Edited",
            attachments: [attachment],
            firstRemovedIndex: 2,
            presentationState: .replacementMessage(
                prompt: "Edited",
                attachments: [attachment]
            )
        )
        let transactionPlan = ChatOutgoingMessageTransactionPlan.replacement(resendPlan: resendPlan)

        let preparedTurn = try workflow.prepare(transactionPlan)

        XCTAssertEqual(preparedTurn.transactionPlan, transactionPlan)
        XCTAssertTrue(preparedTurn.preparedStream.continuationTask === continuationTask)
        XCTAssertEqual(continuationPolicy.beginCount, 1)
        XCTAssertEqual(turnStarter.startRequests.map(\.prompt), ["Edited"])
        XCTAssertEqual(composerConsumer.consumeCount, 0)
        XCTAssertEqual(events.values, ["startTurn"])
    }

    func testPrepareDoesNotStartTurnOrConsumeWhenContinuationBeginFails() {
        let events = EventLog()
        let turnStarter = RecordingTurnStarter(events: events)
        let continuationPolicy = RecordingContinuationTaskPolicy(error: TestError.beginFailed)
        let composerConsumer = RecordingComposerAttachmentConsumer(events: events)
        let workflow = ChatOutgoingTurnPreparationWorkflow(
            turnStarter: turnStarter,
            continuationTaskPolicy: continuationPolicy,
            composerAttachmentStaging: composerConsumer
        )

        XCTAssertThrowsError(
            try workflow.prepareNewMessage(text: "Hello")
        ) { error in
            XCTAssertEqual(error as? TestError, .beginFailed)
        }

        XCTAssertEqual(continuationPolicy.beginCount, 1)
        XCTAssertEqual(composerConsumer.pendingAttachmentsSnapshotCount, 0)
        XCTAssertTrue(turnStarter.startRequests.isEmpty)
        XCTAssertEqual(composerConsumer.consumeCount, 0)
        XCTAssertTrue(events.values.isEmpty)
    }

    func testPrepareNewMessageFinishesContinuationAsFailureAndDoesNotConsumeWhenStartTurnFails() {
        let events = EventLog()
        let turnStarter = RecordingTurnStarter(
            events: events,
            error: TestError.startFailed
        )
        let continuationTask = ChatContinuationTask()
        let backgroundTask = CapturingContinuationBackgroundTask()
        continuationTask.attach(backgroundTask)
        let continuationPolicy = RecordingContinuationTaskPolicy(task: continuationTask)
        let composerConsumer = RecordingComposerAttachmentConsumer(events: events)
        let attachment = makeAttachment()
        composerConsumer.stagedAttachments = [attachment]
        let workflow = ChatOutgoingTurnPreparationWorkflow(
            turnStarter: turnStarter,
            continuationTaskPolicy: continuationPolicy,
            composerAttachmentStaging: composerConsumer
        )

        XCTAssertThrowsError(
            try workflow.prepareNewMessage(text: "Hello")
        ) { error in
            XCTAssertEqual(error as? TestError, .startFailed)
        }

        XCTAssertEqual(continuationPolicy.beginCount, 1)
        XCTAssertEqual(composerConsumer.pendingAttachmentsSnapshotCount, 1)
        XCTAssertEqual(turnStarter.startRequests.map(\.prompt), ["Hello"])
        XCTAssertEqual(turnStarter.startRequests.first?.attachments, [attachment])
        XCTAssertEqual(composerConsumer.consumeCount, 0)
        XCTAssertEqual(composerConsumer.stagedAttachments, [attachment])
        XCTAssertEqual(backgroundTask.completedSuccesses, [false])
        XCTAssertEqual(events.values, ["startTurn"])
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
private final class EventLog {
    private(set) var values: [String] = []

    func append(_ event: String) {
        values.append(event)
    }
}

@MainActor
private final class RecordingTurnStarter: ChatAssistantResponseTurnStarting {
    struct Request: Equatable {
        var prompt: String
        var attachments: [ChatAttachment]
        var userMessageID: UUID
        var replacingUserMessageID: UUID?
    }

    private let events: EventLog
    private let error: Error?
    private(set) var startRequests: [Request] = []

    init(
        events: EventLog,
        error: Error? = nil
    ) {
        self.events = events
        self.error = error
    }

    func startTurn(
        prompt: String,
        attachments: [ChatAttachment],
        userMessageID: UUID,
        replacingUserMessageID: UUID?
    ) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
        events.append("startTurn")
        startRequests.append(
            Request(
                prompt: prompt,
                attachments: attachments,
                userMessageID: userMessageID,
                replacingUserMessageID: replacingUserMessageID
            )
        )

        if let error {
            throw error
        }

        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
private final class RecordingContinuationTaskPolicy: ChatAssistantResponseContinuationTaskPolicy {
    private let task: ChatContinuationTask?
    private let error: Error?
    private(set) var beginCount = 0

    init(
        task: ChatContinuationTask? = nil,
        error: Error? = nil
    ) {
        self.task = task
        self.error = error
    }

    func beginResponseTaskIfNeeded() throws -> ChatContinuationTask? {
        beginCount += 1
        if let error {
            throw error
        }

        return task
    }
}

@MainActor
private final class RecordingComposerAttachmentConsumer: ChatOutgoingTurnComposerAttachmentStaging {
    private let events: EventLog
    var stagedAttachments: [ChatAttachment] = []
    private(set) var pendingAttachmentsSnapshotCount = 0
    private(set) var consumeCount = 0

    var pendingAttachments: [ChatAttachment] {
        pendingAttachmentsSnapshotCount += 1
        return stagedAttachments
    }

    init(events: EventLog) {
        self.events = events
    }

    func consumePendingAttachments() -> [ChatAttachment] {
        consumeCount += 1
        events.append("consume")
        let attachments = stagedAttachments
        stagedAttachments.removeAll()
        return attachments
    }
}

@MainActor
private final class CapturingContinuationBackgroundTask: ChatContinuationBackgroundTask {
    let progress: Progress
    var expirationHandler: (@MainActor () -> Void)?
    private(set) var completedSuccesses: [Bool] = []

    init(progress: Progress = Progress(totalUnitCount: 0)) {
        self.progress = progress
    }

    func setTaskCompleted(success: Bool) {
        completedSuccesses.append(success)
    }
}

private enum TestError: Error {
    case beginFailed
    case startFailed
}
