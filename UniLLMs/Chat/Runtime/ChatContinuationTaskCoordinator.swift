//
//  ChatContinuationTaskCoordinator.swift
//  UniLLMs
//
//  Keeps a user-started chat response eligible for iOS continuous background processing.
//  Created by Codex on 2026/6/3.
//

import BackgroundTasks
import Foundation

@MainActor
protocol ChatContinuationBackgroundTask: AnyObject {
    var progress: Progress { get }
    var expirationHandler: (@MainActor () -> Void)? { get set }

    func setTaskCompleted(success: Bool)
}

@MainActor
final class SystemChatContinuationBackgroundTask: ChatContinuationBackgroundTask {
    private let task: BGContinuedProcessingTask
    private var currentExpirationHandler: (@MainActor () -> Void)?

    init(task: BGContinuedProcessingTask) {
        self.task = task
    }

    var progress: Progress {
        task.progress
    }

    var expirationHandler: (@MainActor () -> Void)? {
        get {
            currentExpirationHandler
        }
        set {
            currentExpirationHandler = newValue
            guard let newValue else {
                task.expirationHandler = nil
                return
            }

            task.expirationHandler = {
                Task { @MainActor in
                    newValue()
                }
            }
        }
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

@MainActor
protocol ChatContinuationTaskScheduling: AnyObject {
    func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping @MainActor (BGTask) -> Void
    ) -> Bool

    func submit(_ request: BGTaskRequest) throws
}

final class SystemChatContinuationTaskScheduler: ChatContinuationTaskScheduling {
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    @MainActor
    func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping @MainActor (BGTask) -> Void
    ) -> Bool {
        scheduler.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { task in
            Task { @MainActor in
                launchHandler(task)
            }
        }
    }

    @MainActor
    func submit(_ request: BGTaskRequest) throws {
        try scheduler.submit(request)
    }
}

enum ChatContinuationTaskError: LocalizedError {
    case registrationFailed(String)
    case submissionFailed(Error)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(identifier):
            return String.localizedStringWithFormat(
                String(localized: "background_runtime.error.registration_failed_format"),
                identifier
            )
        case let .submissionFailed(error):
            return String.localizedStringWithFormat(
                String(localized: "background_runtime.error.submission_failed_format"),
                error.localizedDescription
            )
        }
    }
}

final class ChatContinuationTaskCoordinator {
    private let scheduler: any ChatContinuationTaskScheduling
    private let makeRequestPlan: () -> ChatContinuationTaskRequestPlan
    @MainActor
    private var continuationTasks: [String: ChatContinuationTask] = [:]
    @MainActor
    private var registeredIdentifiers: Set<String> = []

    @MainActor
    var activeTaskCount: Int {
        continuationTasks.count
    }

    convenience init(
        makeRequestPlan: @escaping () -> ChatContinuationTaskRequestPlan = {
            ChatContinuationTaskRequestPlan.make()
        }
    ) {
        self.init(
            scheduler: SystemChatContinuationTaskScheduler(),
            makeRequestPlan: makeRequestPlan
        )
    }

    init(
        scheduler: any ChatContinuationTaskScheduling,
        makeRequestPlan: @escaping () -> ChatContinuationTaskRequestPlan = {
            ChatContinuationTaskRequestPlan.make()
        }
    ) {
        self.scheduler = scheduler
        self.makeRequestPlan = makeRequestPlan
    }

    @MainActor
    func beginResponseTask() throws -> ChatContinuationTask {
        let requestPlan = makeRequestPlan()
        let identifier = requestPlan.identifier
        let task = ChatContinuationTask()
        continuationTasks[identifier] = task
        task.onCompletion = { @MainActor [weak self, weak task] in
            guard let self,
                  let task,
                  self.continuationTasks[identifier] === task else {
                return
            }

            self.continuationTasks[identifier] = nil
        }

        guard register(identifier: requestPlan.registrationIdentifier) else {
            continuationTasks[identifier] = nil
            throw ChatContinuationTaskError.registrationFailed(requestPlan.registrationIdentifier)
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: requestPlan.identifier,
            title: String(localized: "background_runtime.task.title"),
            subtitle: String(localized: "background_runtime.task.subtitle.generating_response")
        )
        request.strategy = .fail

        do {
            try scheduler.submit(request)
            return task
        } catch {
            continuationTasks[identifier] = nil
            throw ChatContinuationTaskError.submissionFailed(error)
        }
    }

    @MainActor
    private func register(identifier: String) -> Bool {
        guard !registeredIdentifiers.contains(identifier) else {
            return true
        }

        let didRegister = scheduler.register(
            forTaskWithIdentifier: identifier
        ) { [weak self] task in
            self?.handle(task)
        }
        if didRegister {
            registeredIdentifiers.insert(identifier)
        }
        return didRegister
    }

    @MainActor
    private func handle(_ task: BGTask) {
        guard let continuationTask = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }

        guard let activeTask = continuationTasks[task.identifier] else {
            continuationTask.setTaskCompleted(success: false)
            return
        }

        activeTask.attach(
            SystemChatContinuationBackgroundTask(task: continuationTask)
        )
    }
}

@MainActor
final class ChatContinuationTask {
    var onExpiration: (@MainActor () -> Void)?
    var onCompletion: (@MainActor () -> Void)?

    private var task: (any ChatContinuationBackgroundTask)?
    private var isFinished = false
    private var finishedSuccessfully = false
    private var hasSentCompletion = false
    private var receivedCharacterCount = 0

    func attach(_ task: any ChatContinuationBackgroundTask) {
        guard self.task == nil else {
            task.setTaskCompleted(success: false)
            return
        }

        self.task = task
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = 1
        task.expirationHandler = { [weak self] in
            self?.expire()
        }
        updateProgress()

        if isFinished {
            completeAttachedTask(success: finishedSuccessfully)
        }
    }

    func report(delta: ChatResponseDelta) {
        guard !isFinished else {
            return
        }

        let characterCount = Self.characterCount(in: delta)
        guard characterCount > 0 else {
            return
        }

        receivedCharacterCount += characterCount
        updateProgress()
    }

    func finish(success: Bool) {
        guard !isFinished else {
            return
        }

        isFinished = true
        finishedSuccessfully = success
        guard task != nil else {
            sendCompletionIfNeeded()
            return
        }

        completeAttachedTask(success: success)
    }

    private func expire() {
        guard !isFinished else {
            return
        }

        finish(success: false)
        onExpiration?()
    }

    private func updateProgress() {
        guard let task else {
            return
        }

        let completedUnitCount = max(Int64(receivedCharacterCount), 1)
        task.progress.totalUnitCount = max(100, completedUnitCount + 120)
        task.progress.completedUnitCount = completedUnitCount
    }

    private func completeAttachedTask(success: Bool) {
        guard let task else {
            return
        }

        task.progress.totalUnitCount = max(task.progress.totalUnitCount, 1)
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: success)
        self.task = nil
        sendCompletionIfNeeded()
    }

    private func sendCompletionIfNeeded() {
        guard !hasSentCompletion else {
            return
        }

        hasSentCompletion = true
        onCompletion?()
    }

    private static func characterCount(in delta: ChatResponseDelta) -> Int {
        var count = 0
        for part in delta.displayParts {
            switch part {
            case let .reasoning(text),
                 let .content(text):
                count += text.count
            case .toolEvent:
                count += 12
            }
        }
        return count == 0
            ? delta.content.count + delta.reasoning.count + (delta.toolCalls.count * 12)
            : count
    }
}
