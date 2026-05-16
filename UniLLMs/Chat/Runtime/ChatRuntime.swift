//
//  ChatRuntime.swift
//  UniLLMs
//
//  Coordinates chat turn state, model selection, context building, and response stream lifecycle.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

enum ChatRuntimeError: LocalizedError, Equatable {
    case turnAlreadyInProgress
    case missingModelSelection
    case selectedProviderUnavailable

    var errorDescription: String? {
        switch self {
        case .turnAlreadyInProgress:
            return "Wait for the current response to finish."
        case .missingModelSelection:
            return "Select a model first."
        case .selectedProviderUnavailable:
            return "The selected provider is no longer available."
        }
    }
}

final class ChatRuntime {
    static let historyDidChangeNotification = Notification.Name("ChatRuntimeHistoryDidChangeNotification")

    private struct TurnProgress {
        var timelineAccumulator = ChatTimelineAccumulator()

        var hasPersistableProgress: Bool {
            !timelineAccumulator.events.isEmpty
        }

        mutating func append(displayDelta delta: ChatResponseDelta, timestamp: Date) {
            timelineAccumulator.appendDisplayDelta(delta, timestamp: timestamp)
        }

        mutating func append(timelineEvent kind: ChatTimelineEvent.Kind, timestamp: Date) {
            timelineAccumulator.append(
                ChatTimelineEvent(
                    timestamp: timestamp,
                    kind: kind
                )
            )
        }

        func finishedEvents() -> [ChatTimelineEvent] {
            timelineAccumulator.events
        }
    }

    private let providerStore: LLMsProviderStore
    private let providerManager: LLMsProviderManager
    private let contextBuilder: ChatContextBuilder
    private let turnRunner: ChatTurnRunner
    private let historyStore: (any ChatHistoryStore)?
    private let clock: any AppClock
    private var currentSession = ChatSession(title: "New Chat")
    private var conversationTimeline: [ChatTimelineEvent] = []
    private var activeTurnID: UUID?
    private var historyPersistenceTask: Task<Void, Never>?

    init(
        providerStore: LLMsProviderStore,
        providerManager: LLMsProviderManager,
        contextBuilder: ChatContextBuilder,
        turnRunner: ChatTurnRunner,
        historyStore: (any ChatHistoryStore)? = nil,
        clock: any AppClock = SystemAppClock()
    ) {
        self.providerStore = providerStore
        self.providerManager = providerManager
        self.contextBuilder = contextBuilder
        self.turnRunner = turnRunner
        self.historyStore = historyStore
        self.clock = clock
    }

    var currentSessionID: UUID {
        currentSession.id
    }

    func startTurn(prompt: String) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
        guard activeTurnID == nil else {
            throw ChatRuntimeError.turnAlreadyInProgress
        }

        guard let selection = providerManager.fetchSelectedModelSelection() else {
            throw ChatRuntimeError.missingModelSelection
        }

        guard let provider = providerStore.fetchProvider(id: selection.providerID) else {
            throw ChatRuntimeError.selectedProviderUnavailable
        }

        let turnID = UUID()
        let sentAt = clock.now
        if conversationTimeline.isEmpty {
            currentSession.title = Self.makeSessionTitle(from: prompt)
            currentSession.createdAt = sentAt
        }
        currentSession.updatedAt = sentAt

        let userEvent = ChatTimelineEvent(
            timestamp: sentAt,
            kind: .userMessage(text: prompt)
        )
        let requestTimeline = conversationTimeline + [userEvent]
        let requestMessages = ChatTimelineEvent.messages(from: requestTimeline)
        conversationTimeline.append(userEvent)
        activeTurnID = turnID
        persistCurrentHistorySnapshot()

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                var turnProgress = TurnProgress()

                do {
                    guard let self else {
                        continuation.finish()
                        return
                    }

                    let context = await self.contextBuilder.buildContext(
                        session: self.currentSession,
                        messages: requestMessages,
                        includeTools: self.providerManager.provider(provider, supports: .tools)
                    )
                    let stream = self.turnRunner.streamResponse(
                        provider: provider,
                        modelID: selection.modelID,
                        context: context
                    )

                    for try await event in stream {
                        try Task.checkCancellation()

                        switch event {
                        case let .displayDelta(delta):
                            turnProgress.append(displayDelta: delta, timestamp: self.clock.now)
                            continuation.yield(delta)
                        case let .timelineEvent(kind):
                            turnProgress.append(timelineEvent: kind, timestamp: self.clock.now)
                        }
                    }

                    self.finishTurn(
                        id: turnID,
                        userEventID: userEvent.id,
                        progress: turnProgress,
                        shouldKeepUserMessage: true
                    )
                    continuation.finish()
                } catch is CancellationError {
                    self?.finishTurn(
                        id: turnID,
                        userEventID: userEvent.id,
                        progress: turnProgress,
                        shouldKeepUserMessage: true
                    )
                    continuation.finish()
                } catch {
                    self?.finishTurn(
                        id: turnID,
                        userEventID: userEvent.id,
                        progress: turnProgress,
                        shouldKeepUserMessage: turnProgress.hasPersistableProgress
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func resetConversation() {
        conversationTimeline = []
        currentSession = ChatSession(title: "New Chat")
    }

    func loadConversation(session: ChatSession, events: [ChatTimelineEvent]) {
        guard activeTurnID == nil else {
            return
        }

        currentSession = session
        conversationTimeline = ChatTimelineEvent.sortedChronologically(events)
    }

    private func finishTurn(
        id turnID: UUID,
        userEventID: UUID,
        progress: TurnProgress,
        shouldKeepUserMessage: Bool
    ) {
        guard activeTurnID == turnID else {
            return
        }

        let turnEvents = progress.finishedEvents()
        if !turnEvents.isEmpty {
            conversationTimeline.append(contentsOf: turnEvents)
            if let lastEvent = turnEvents.last,
               lastEvent.timestamp > currentSession.updatedAt {
                currentSession.updatedAt = lastEvent.timestamp
            }
        } else if !shouldKeepUserMessage {
            conversationTimeline.removeAll { $0.id == userEventID }
        }

        activeTurnID = nil
        persistCurrentHistorySnapshot()
    }

    private func persistCurrentHistorySnapshot() {
        guard let historyStore else {
            return
        }

        let session = currentSession
        let events = conversationTimeline
        let previousTask = historyPersistenceTask
        historyPersistenceTask = Task { @MainActor [previousTask, historyStore] in
            if let previousTask {
                await previousTask.value
            }

            if events.isEmpty {
                try? await historyStore.deleteSession(id: session.id)
            } else {
                try? await historyStore.saveSession(session)
                try? await historyStore.saveEvents(events, sessionID: session.id)
            }
            NotificationCenter.default.post(
                name: Self.historyDidChangeNotification,
                object: nil
            )
        }
    }

    private static func makeSessionTitle(from prompt: String) -> String {
        let collapsedPrompt = prompt
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsedPrompt.isEmpty else {
            return "New Chat"
        }

        return collapsedPrompt
    }
}
