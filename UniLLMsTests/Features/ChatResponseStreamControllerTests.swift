//
//  ChatResponseStreamControllerTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatResponseStreamControllerTests: XCTestCase {
    func testSuccessfulStreamDeliversDeltaAndFinishes() async {
        let controller = ChatResponseStreamController()
        var receivedDeltas: [ChatResponseDelta] = []
        var finishedResults: [Bool] = []

        controller.activate(
            responseStream: Self.stream(deltas: [ChatResponseDelta(content: "Hello")]),
            continuationTask: nil,
            handlers: ChatResponseStreamController.Handlers(
                didReceiveDelta: { receivedDeltas.append($0) },
                didFail: { _ in XCTFail("Expected success.") },
                didFinish: { finishedResults.append($0) }
            )
        )

        await waitUntil { finishedResults.count == 1 }

        XCTAssertEqual(receivedDeltas.map(\.content), ["Hello"])
        XCTAssertEqual(finishedResults, [true])
        XCTAssertFalse(controller.isActive)
    }

    func testFailingStreamReportsFailureThenFinishesUnsuccessfully() async {
        let controller = ChatResponseStreamController()
        var receivedErrorDescriptions: [String] = []
        var finishedResults: [Bool] = []

        controller.activate(
            responseStream: Self.failingStream(error: StreamFailure.sample),
            continuationTask: nil,
            handlers: ChatResponseStreamController.Handlers(
                didReceiveDelta: { _ in XCTFail("Expected no deltas.") },
                didFail: { receivedErrorDescriptions.append($0.localizedDescription) },
                didFinish: { finishedResults.append($0) }
            )
        )

        await waitUntil { finishedResults.count == 1 }

        XCTAssertEqual(receivedErrorDescriptions, [StreamFailure.sample.localizedDescription])
        XCTAssertEqual(finishedResults, [false])
        XCTAssertFalse(controller.isActive)
    }

    func testCancelFinishesUnsuccessfully() async {
        let controller = ChatResponseStreamController()
        var continuation: AsyncThrowingStream<ChatResponseDelta, Error>.Continuation?
        let stream = AsyncThrowingStream<ChatResponseDelta, Error> { streamContinuation in
            continuation = streamContinuation
        }
        var finishedResults: [Bool] = []
        var receivedDeltas: [ChatResponseDelta] = []

        controller.activate(
            responseStream: stream,
            continuationTask: nil,
            handlers: ChatResponseStreamController.Handlers(
                didReceiveDelta: { receivedDeltas.append($0) },
                didFail: { _ in XCTFail("Expected cancellation path.") },
                didFinish: { finishedResults.append($0) }
            )
        )

        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.cancel())
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(finishedResults, [false])
        continuation?.yield(ChatResponseDelta(content: "Late"))
        continuation?.finish()
        await waitUntil { finishedResults.count == 1 }

        XCTAssertEqual(receivedDeltas, [])
        XCTAssertEqual(finishedResults, [false])
        XCTAssertFalse(controller.isActive)
    }

    func testCancelAllowsImmediateReactivation() async {
        let controller = ChatResponseStreamController()
        let firstStream = AsyncThrowingStream<ChatResponseDelta, Error> { _ in }
        var secondFinishedResults: [Bool] = []

        XCTAssertTrue(
            controller.activate(
                responseStream: firstStream,
                continuationTask: nil,
                handlers: ChatResponseStreamController.Handlers(
                    didReceiveDelta: { _ in },
                    didFail: { _ in XCTFail("Expected cancellation path.") },
                    didFinish: { _ in }
                )
            )
        )
        XCTAssertTrue(controller.cancel())

        XCTAssertTrue(
            controller.activate(
                responseStream: Self.stream(deltas: [ChatResponseDelta(content: "Next")]),
                continuationTask: nil,
                handlers: ChatResponseStreamController.Handlers(
                    didReceiveDelta: { _ in },
                    didFail: { _ in XCTFail("Expected success.") },
                    didFinish: { secondFinishedResults.append($0) }
                )
            )
        )

        await waitUntil { secondFinishedResults.count == 1 }

        XCTAssertEqual(secondFinishedResults, [true])
        XCTAssertFalse(controller.isActive)
    }

    func testSuccessfulStreamFinishesContinuationTaskSuccessfully() async {
        let controller = ChatResponseStreamController()
        let continuationTask = ChatContinuationTask()
        let backgroundTask = CapturingResponseContinuationBackgroundTask()
        continuationTask.attach(backgroundTask)
        var receivedDeltas: [ChatResponseDelta] = []
        var finishedResults: [Bool] = []

        controller.activate(
            responseStream: Self.stream(deltas: [ChatResponseDelta(content: "Hello")]),
            continuationTask: continuationTask,
            handlers: ChatResponseStreamController.Handlers(
                didReceiveDelta: { delta in
                    receivedDeltas.append(delta)
                    controller.report(delta: delta)
                },
                didFail: { _ in XCTFail("Expected success.") },
                didFinish: { finishedResults.append($0) }
            )
        )

        await waitUntil { finishedResults.count == 1 }

        XCTAssertEqual(receivedDeltas.map(\.content), ["Hello"])
        XCTAssertEqual(finishedResults, [true])
        XCTAssertEqual(backgroundTask.completedSuccesses, [true])
        XCTAssertEqual(
            backgroundTask.progress.completedUnitCount,
            backgroundTask.progress.totalUnitCount
        )
    }

    func testFailingStreamFinishesContinuationTaskUnsuccessfully() async {
        let controller = ChatResponseStreamController()
        let continuationTask = ChatContinuationTask()
        let backgroundTask = CapturingResponseContinuationBackgroundTask()
        continuationTask.attach(backgroundTask)
        var failureDescriptions: [String] = []
        var finishedResults: [Bool] = []

        controller.activate(
            responseStream: Self.failingStream(error: StreamFailure.sample),
            continuationTask: continuationTask,
            handlers: ChatResponseStreamController.Handlers(
                didReceiveDelta: { _ in XCTFail("Expected no deltas.") },
                didFail: { failureDescriptions.append($0.localizedDescription) },
                didFinish: { finishedResults.append($0) }
            )
        )

        await waitUntil { finishedResults.count == 1 }

        XCTAssertEqual(failureDescriptions, [StreamFailure.sample.localizedDescription])
        XCTAssertEqual(finishedResults, [false])
        XCTAssertEqual(backgroundTask.completedSuccesses, [false])
    }

    func testContinuationTaskExpirationCancelsStream() async {
        let controller = ChatResponseStreamController()
        let continuationTask = ChatContinuationTask()
        let backgroundTask = CapturingResponseContinuationBackgroundTask()
        continuationTask.attach(backgroundTask)
        let stream = AsyncThrowingStream<ChatResponseDelta, Error> { _ in }
        var finishedResults: [Bool] = []

        controller.activate(
            responseStream: stream,
            continuationTask: continuationTask,
            handlers: ChatResponseStreamController.Handlers(
                didReceiveDelta: { _ in XCTFail("Expected expiration before deltas.") },
                didFail: { _ in XCTFail("Expected cancellation path.") },
                didFinish: { finishedResults.append($0) }
            )
        )

        backgroundTask.expirationHandler?()
        await waitUntil { finishedResults.count == 1 }

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(finishedResults, [false])
        XCTAssertEqual(backgroundTask.completedSuccesses, [false])
    }

    private static func stream(
        deltas: [ChatResponseDelta]
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            for delta in deltas {
                continuation.yield(delta)
            }
            continuation.finish()
        }
    }

    private static func failingStream(
        error: Error
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    private func waitUntil(
        _ predicate: () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if predicate() {
                return
            }
            await Task.yield()
        }
    }
}

private enum StreamFailure: LocalizedError {
    case sample

    var errorDescription: String? {
        "Stream failed."
    }
}

@MainActor
private final class CapturingResponseContinuationBackgroundTask: ChatContinuationBackgroundTask {
    let progress = Progress(totalUnitCount: 0)
    var expirationHandler: (@MainActor () -> Void)?
    private(set) var completedSuccesses: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completedSuccesses.append(success)
    }
}
