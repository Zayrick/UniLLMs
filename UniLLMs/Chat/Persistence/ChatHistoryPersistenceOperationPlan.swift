//
//  ChatHistoryPersistenceOperationPlan.swift
//  UniLLMs
//
//  Describes the store work required for one chat history persistence snapshot.
//

import Foundation

nonisolated struct ChatHistoryPersistenceOperationPlan: Equatable {
    nonisolated enum StoreOperation: Equatable {
        case deleteSession(UUID)
        case saveSnapshot(ChatSession, [ChatTimelineEvent])
    }

    var storeOperation: StoreOperation?

    init(
        session: ChatSession,
        events: [ChatTimelineEvent],
        privacyModeEnabled: Bool
    ) {
        if privacyModeEnabled {
            storeOperation = nil
        } else if events.isEmpty {
            storeOperation = .deleteSession(session.id)
        } else {
            storeOperation = .saveSnapshot(session, events)
        }
    }

    var requiresStoreWrite: Bool {
        storeOperation != nil
    }

    func perform(on historyStore: any ChatHistoryStore) async throws {
        switch storeOperation {
        case nil:
            return
        case let .deleteSession(sessionID):
            try await historyStore.deleteSession(id: sessionID)
        case let .saveSnapshot(session, events):
            try await historyStore.saveSession(session)
            try await historyStore.saveEvents(events, sessionID: session.id)
        }
    }
}
