//
//  ChatContinuationTaskCoordinatorTests.swift
//  UniLLMsTests
//

import BackgroundTasks
import XCTest
@testable import UniLLMs

@MainActor
final class ChatContinuationTaskCoordinatorTests: XCTestCase {
    func testBeginResponseTaskRegistersAndSubmitsRequestPlanIdentifier() throws {
        let scheduler = CapturingContinuationTaskScheduler()
        let coordinator = ChatContinuationTaskCoordinator(
            scheduler: scheduler,
            makeRequestPlan: {
                ChatContinuationTaskRequestPlan(suffix: "ABC")
            }
        )

        _ = try coordinator.beginResponseTask()

        XCTAssertEqual(scheduler.registeredIdentifiers, ["Zayrick.UniLLMs.chatTurn.ABC"])
        XCTAssertEqual(scheduler.submittedIdentifiers, ["Zayrick.UniLLMs.chatTurn.ABC"])
        XCTAssertEqual(coordinator.activeTaskCount, 1)
    }

    func testBeginResponseTaskCleansActiveTaskWhenRegistrationFails() {
        let scheduler = CapturingContinuationTaskScheduler()
        scheduler.registerResult = false
        let coordinator = ChatContinuationTaskCoordinator(
            scheduler: scheduler,
            makeRequestPlan: {
                ChatContinuationTaskRequestPlan(suffix: "ABC")
            }
        )

        XCTAssertThrowsError(try coordinator.beginResponseTask()) { error in
            guard case let ChatContinuationTaskError.registrationFailed(identifier) = error else {
                XCTFail("Expected registrationFailed error.")
                return
            }
            XCTAssertEqual(identifier, "Zayrick.UniLLMs.chatTurn.ABC")
        }

        XCTAssertEqual(scheduler.registeredIdentifiers, ["Zayrick.UniLLMs.chatTurn.ABC"])
        XCTAssertTrue(scheduler.submittedIdentifiers.isEmpty)
        XCTAssertEqual(coordinator.activeTaskCount, 0)
    }

    func testBeginResponseTaskCleansActiveTaskWhenSubmissionFails() {
        let scheduler = CapturingContinuationTaskScheduler()
        scheduler.submitError = ContinuationSchedulerFailure()
        let coordinator = ChatContinuationTaskCoordinator(
            scheduler: scheduler,
            makeRequestPlan: {
                ChatContinuationTaskRequestPlan(suffix: "ABC")
            }
        )

        XCTAssertThrowsError(try coordinator.beginResponseTask()) { error in
            guard case ChatContinuationTaskError.submissionFailed = error else {
                XCTFail("Expected submissionFailed error.")
                return
            }
        }

        XCTAssertEqual(scheduler.registeredIdentifiers, ["Zayrick.UniLLMs.chatTurn.ABC"])
        XCTAssertEqual(scheduler.submittedIdentifiers, ["Zayrick.UniLLMs.chatTurn.ABC"])
        XCTAssertEqual(coordinator.activeTaskCount, 0)
    }

    func testBeginResponseTaskReusesSuccessfulRegistrationForRepeatedIdentifier() throws {
        let scheduler = CapturingContinuationTaskScheduler()
        let coordinator = ChatContinuationTaskCoordinator(
            scheduler: scheduler,
            makeRequestPlan: {
                ChatContinuationTaskRequestPlan(suffix: "ABC")
            }
        )

        let firstTask = try coordinator.beginResponseTask()
        firstTask.finish(success: true)
        _ = try coordinator.beginResponseTask()

        XCTAssertEqual(scheduler.registeredIdentifiers, ["Zayrick.UniLLMs.chatTurn.ABC"])
        XCTAssertEqual(
            scheduler.submittedIdentifiers,
            [
                "Zayrick.UniLLMs.chatTurn.ABC",
                "Zayrick.UniLLMs.chatTurn.ABC"
            ]
        )
        XCTAssertEqual(coordinator.activeTaskCount, 1)
    }

    func testBeginResponseTaskRetriesRegistrationAfterRegistrationFailure() throws {
        let scheduler = CapturingContinuationTaskScheduler()
        scheduler.registerResult = false
        let coordinator = ChatContinuationTaskCoordinator(
            scheduler: scheduler,
            makeRequestPlan: {
                ChatContinuationTaskRequestPlan(suffix: "ABC")
            }
        )

        XCTAssertThrowsError(try coordinator.beginResponseTask())
        scheduler.registerResult = true
        _ = try coordinator.beginResponseTask()

        XCTAssertEqual(
            scheduler.registeredIdentifiers,
            [
                "Zayrick.UniLLMs.chatTurn.ABC",
                "Zayrick.UniLLMs.chatTurn.ABC"
            ]
        )
        XCTAssertEqual(scheduler.submittedIdentifiers, ["Zayrick.UniLLMs.chatTurn.ABC"])
        XCTAssertEqual(coordinator.activeTaskCount, 1)
    }

    func testFinishingTaskBeforeSystemAttachCleansActiveTask() throws {
        let scheduler = CapturingContinuationTaskScheduler()
        let coordinator = ChatContinuationTaskCoordinator(
            scheduler: scheduler,
            makeRequestPlan: {
                ChatContinuationTaskRequestPlan(suffix: "ABC")
            }
        )

        let task = try coordinator.beginResponseTask()
        XCTAssertEqual(coordinator.activeTaskCount, 1)

        task.finish(success: true)

        XCTAssertEqual(coordinator.activeTaskCount, 0)
    }

    func testAttachInitializesBackgroundProgressAndExpirationHandler() {
        let task = ChatContinuationTask()
        let backgroundTask = CapturingContinuationBackgroundTask()

        task.attach(backgroundTask)

        XCTAssertEqual(backgroundTask.progress.completedUnitCount, Int64(1))
        XCTAssertEqual(backgroundTask.progress.totalUnitCount, Int64(121))
        XCTAssertNotNil(backgroundTask.expirationHandler)
        XCTAssertTrue(backgroundTask.completedSuccesses.isEmpty)
    }

    func testReportDeltaUpdatesAttachedBackgroundProgress() {
        let task = ChatContinuationTask()
        let backgroundTask = CapturingContinuationBackgroundTask()

        task.attach(backgroundTask)
        task.report(
            delta: ChatResponseDelta(
                displayParts: [
                    .content("Hello"),
                    .reasoning("!!")
                ]
            )
        )

        XCTAssertEqual(backgroundTask.progress.completedUnitCount, Int64(7))
        XCTAssertEqual(backgroundTask.progress.totalUnitCount, Int64(127))
    }

    func testFinishCompletesAttachedBackgroundTaskAndSendsCompletionOnce() {
        let task = ChatContinuationTask()
        let backgroundTask = CapturingContinuationBackgroundTask()
        var completionCount = 0
        task.onCompletion = {
            completionCount += 1
        }

        task.attach(backgroundTask)
        task.finish(success: true)
        task.finish(success: false)

        XCTAssertEqual(backgroundTask.completedSuccesses, [true])
        XCTAssertEqual(
            backgroundTask.progress.completedUnitCount,
            backgroundTask.progress.totalUnitCount
        )
        XCTAssertEqual(completionCount, 1)
    }

    func testFinishedTaskCompletesLaterBackgroundAttachWithoutSendingCompletionAgain() {
        let task = ChatContinuationTask()
        let backgroundTask = CapturingContinuationBackgroundTask()
        var completionCount = 0
        task.onCompletion = {
            completionCount += 1
        }

        task.finish(success: true)
        task.attach(backgroundTask)

        XCTAssertEqual(backgroundTask.completedSuccesses, [true])
        XCTAssertEqual(completionCount, 1)
    }

    func testExpirationCompletesAttachedBackgroundTaskAsFailureAndCallsHandlers() {
        let task = ChatContinuationTask()
        let backgroundTask = CapturingContinuationBackgroundTask()
        var expirationCount = 0
        var completionCount = 0
        task.onExpiration = {
            expirationCount += 1
        }
        task.onCompletion = {
            completionCount += 1
        }

        task.attach(backgroundTask)
        backgroundTask.expirationHandler?()

        XCTAssertEqual(backgroundTask.completedSuccesses, [false])
        XCTAssertEqual(expirationCount, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testSecondAttachRejectsNewBackgroundTask() {
        let task = ChatContinuationTask()
        let firstBackgroundTask = CapturingContinuationBackgroundTask()
        let secondBackgroundTask = CapturingContinuationBackgroundTask()

        task.attach(firstBackgroundTask)
        task.attach(secondBackgroundTask)

        XCTAssertTrue(firstBackgroundTask.completedSuccesses.isEmpty)
        XCTAssertEqual(secondBackgroundTask.completedSuccesses, [false])
    }
}

@MainActor
private final class CapturingContinuationTaskScheduler: ChatContinuationTaskScheduling {
    var registerResult = true
    var submitError: Error?
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submittedIdentifiers: [String] = []

    func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping @MainActor (BGTask) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        return registerResult
    }

    func submit(_ request: BGTaskRequest) throws {
        submittedIdentifiers.append(request.identifier)
        if let submitError {
            throw submitError
        }
    }
}

private struct ContinuationSchedulerFailure: Error {}

@MainActor
private final class CapturingContinuationBackgroundTask: ChatContinuationBackgroundTask {
    let progress: Progress
    var expirationHandler: (@MainActor () -> Void)?
    private(set) var completedSuccesses: [Bool] = []

    init(
        progress: Progress = Progress(totalUnitCount: 0)
    ) {
        self.progress = progress
    }

    func setTaskCompleted(success: Bool) {
        completedSuccesses.append(success)
    }
}
