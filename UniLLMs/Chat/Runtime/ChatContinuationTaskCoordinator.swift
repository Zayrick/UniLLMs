//
//  ChatContinuationTaskCoordinator.swift
//  UniLLMs
//
//  Keeps a user-started chat response eligible for iOS continuous background processing.
//  Created by Codex on 2026/6/3.
//

import BackgroundTasks
import Foundation

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

@MainActor
final class ChatContinuationTaskCoordinator {
    private static let taskIdentifierPrefix = "Zayrick.UniLLMs.chatTurn"

    private let scheduler: BGTaskScheduler
    private var continuationTasks: [String: ChatContinuationTask] = [:]

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    func beginResponseTask() throws -> ChatContinuationTask {
        let identifier = Self.makeTaskIdentifier()
        let task = ChatContinuationTask()
        continuationTasks[identifier] = task
        task.onCompletion = { [weak self, weak task] in
            guard let self,
                  let task,
                  self.continuationTasks[identifier] === task else {
                return
            }

            self.continuationTasks[identifier] = nil
        }

        guard register(identifier: identifier) else {
            continuationTasks[identifier] = nil
            throw ChatContinuationTaskError.registrationFailed(identifier)
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
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

    private func register(identifier: String) -> Bool {
        scheduler.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { [weak self] task in
            self?.handle(task)
        }
    }

    private func handle(_ task: BGTask) {
        guard let continuationTask = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }

        guard let activeTask = continuationTasks[task.identifier] else {
            continuationTask.setTaskCompleted(success: false)
            return
        }

        activeTask.attach(continuationTask)
    }

    private static func makeTaskIdentifier() -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "\(taskIdentifierPrefix).\(suffix)"
    }
}

@MainActor
final class ChatContinuationTask {
    var onExpiration: (() -> Void)?
    var onCompletion: (() -> Void)?

    private var task: BGContinuedProcessingTask?
    private var isFinished = false
    private var finishedSuccessfully = false
    private var receivedCharacterCount = 0

    func attach(_ task: BGContinuedProcessingTask) {
        guard self.task == nil else {
            task.setTaskCompleted(success: false)
            return
        }

        self.task = task
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = 1
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.expire()
            }
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
        completeAttachedTask(success: success)
    }

    private func expire() {
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
