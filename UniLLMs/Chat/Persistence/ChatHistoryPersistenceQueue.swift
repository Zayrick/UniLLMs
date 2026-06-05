//
//  ChatHistoryPersistenceQueue.swift
//  UniLLMs
//
//  Serializes chat history snapshot persistence and history-change notification delivery.
//  Created by Codex on 2026/6/5.
//

import Foundation

final class ChatHistoryPersistenceQueue {
    private let historyStore: (any ChatHistoryStore)?
    private let notificationName: Notification.Name
    private let notificationCenter: NotificationCenter
    private let didFail: @MainActor (Error) -> Void
    private var pendingTask: Task<Void, Never>?

    init(
        historyStore: (any ChatHistoryStore)?,
        notificationName: Notification.Name,
        notificationCenter: NotificationCenter = .default,
        didFail: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.historyStore = historyStore
        self.notificationName = notificationName
        self.notificationCenter = notificationCenter
        self.didFail = didFail
    }

    func persist(
        session: ChatSession,
        events: [ChatTimelineEvent],
        privacyModeEnabled: Bool
    ) {
        guard let historyStore else {
            return
        }

        let operationPlan = ChatHistoryPersistenceOperationPlan(
            session: session,
            events: events,
            privacyModeEnabled: privacyModeEnabled
        )

        guard operationPlan.requiresStoreWrite else {
            notificationCenter.post(name: notificationName, object: nil)
            return
        }

        let previousTask = pendingTask
        pendingTask = Task { @MainActor [previousTask, historyStore, operationPlan, notificationName, notificationCenter, didFail] in
            if let previousTask {
                await previousTask.value
            }

            do {
                try await operationPlan.perform(on: historyStore)
                notificationCenter.post(name: notificationName, object: nil)
            } catch is CancellationError {
                return
            } catch {
                didFail(error)
            }
        }
    }

    func waitForPendingPersistence() async {
        await pendingTask?.value
    }
}
