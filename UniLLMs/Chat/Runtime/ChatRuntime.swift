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
    case userMessageNotFound

    var errorDescription: String? {
        switch self {
        case .turnAlreadyInProgress:
            return String(localized: .chatResponseInProgress)
        case .missingModelSelection:
            return String(localized: .runtimeErrorModelRequired)
        case .selectedProviderUnavailable:
            return String(localized: .runtimeErrorSelectedProviderUnavailable)
        case .userMessageNotFound:
            return String(localized: .runtimeErrorMessageCouldNotBeEdited)
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

    private struct ArchivedCurrentBranch {
        var prefixMainlineEvents: [ChatTimelineEvent]
        var currentBranchEvents: [ChatTimelineEvent]
        var retainedRevisionEvents: [ChatTimelineEvent]
    }

    private let providerStore: LLMsProviderStore
    private let providerManager: LLMsProviderManager
    private let systemPromptManager: SystemPromptManager
    private let contextBuilder: ChatContextBuilder
    private let turnRunner: ChatTurnRunner
    private let historyStore: (any ChatHistoryStore)?
    private let clock: any AppClock
    private var currentSession = ChatSession(title: String(localized: .chatNewChat))
    private var conversationTimeline: [ChatTimelineEvent] = []
    private var activeTurnID: UUID?
    private var historyPersistenceTask: Task<Void, Never>?
    private(set) var isPrivacyModeEnabled = false

    init(
        providerStore: LLMsProviderStore,
        providerManager: LLMsProviderManager,
        systemPromptManager: SystemPromptManager = SystemPromptManager(),
        contextBuilder: ChatContextBuilder,
        turnRunner: ChatTurnRunner,
        historyStore: (any ChatHistoryStore)? = nil,
        clock: any AppClock = SystemAppClock()
    ) {
        self.providerStore = providerStore
        self.providerManager = providerManager
        self.systemPromptManager = systemPromptManager
        self.contextBuilder = contextBuilder
        self.turnRunner = turnRunner
        self.historyStore = historyStore
        self.clock = clock
    }

    var currentSessionID: UUID {
        currentSession.id
    }

    var selectedSystemPromptID: UUID? {
        currentSession.selectedSystemPromptID
    }

    var currentConversationAttachments: [ChatAttachment] {
        ChatTimelineEvent.attachments(from: conversationTimeline)
    }

    func selectedSystemPrompt() -> SystemPromptRecord? {
        resolvedSelectedSystemPrompt(persistIfCleared: true)
    }

    func selectSystemPrompt(id promptID: UUID) {
        guard systemPromptManager.prompt(id: promptID) != nil else {
            clearSelectedSystemPrompt()
            return
        }

        guard currentSession.selectedSystemPromptID != promptID else {
            return
        }

        currentSession.selectedSystemPromptID = promptID
        persistCurrentSessionMetadataIfNeeded()
    }

    func clearSelectedSystemPrompt() {
        guard currentSession.selectedSystemPromptID != nil else {
            return
        }

        currentSession.selectedSystemPromptID = nil
        persistCurrentSessionMetadataOrDeleteEmptySession()
    }

    func waitForPendingHistoryPersistence() async {
        await historyPersistenceTask?.value
    }

    func messageRevisions(for anchorUserMessageID: UUID) -> [ChatMessageRevision] {
        ChatTimelineEvent.messageRevisions(from: conversationTimeline)[anchorUserMessageID] ?? []
    }

    func switchToMessageRevision(
        anchorUserMessageID: UUID,
        revisionID: UUID
    ) throws -> [ChatTimelineEvent] {
        guard activeTurnID == nil else {
            throw ChatRuntimeError.turnAlreadyInProgress
        }

        guard let selectedRevision = messageRevisions(for: anchorUserMessageID).first(where: { $0.id == revisionID }) else {
            throw ChatRuntimeError.userMessageNotFound
        }

        let switchedAt = clock.now
        let archivedBranch = try archivedCurrentBranch(
            anchoredAt: anchorUserMessageID,
            excludingRevisionID: revisionID
        )
        let currentRevision = ChatMessageRevision(
            anchorUserMessageID: anchorUserMessageID,
            archivedAt: switchedAt,
            events: archivedBranch.currentBranchEvents
        )
        var updatedTimeline = archivedBranch.prefixMainlineEvents + archivedBranch.retainedRevisionEvents
        if !currentRevision.events.isEmpty {
            updatedTimeline.append(
                ChatTimelineEvent(
                    timestamp: switchedAt,
                    kind: .messageRevision(currentRevision)
                )
            )
        }
        updatedTimeline.append(contentsOf: selectedRevision.events.map(\.timelineEvent))

        conversationTimeline = updatedTimeline
        currentSession.updatedAt = switchedAt
        persistCurrentHistorySnapshot()
        return conversationTimeline
    }

    func startTurn(
        prompt: String,
        attachments: [ChatAttachment] = [],
        userMessageID: UUID = UUID(),
        replacingUserMessageID: UUID? = nil
    ) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
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
        if let replacingUserMessageID {
            let archivedBranch = try archivedCurrentBranch(anchoredAt: replacingUserMessageID)
            let revision = ChatMessageRevision(
                anchorUserMessageID: replacingUserMessageID,
                archivedAt: sentAt,
                events: archivedBranch.currentBranchEvents
            )
            conversationTimeline = archivedBranch.prefixMainlineEvents + archivedBranch.retainedRevisionEvents
            if !revision.events.isEmpty {
                conversationTimeline.append(
                    ChatTimelineEvent(
                        timestamp: sentAt,
                        kind: .messageRevision(revision)
                    )
                )
            }
        }

        let turnSystemPrompt = resolvedSystemPromptForNextTurn()
        if ChatTimelineEvent.messages(from: conversationTimeline).isEmpty {
            currentSession.title = Self.makeSessionTitle(from: prompt, attachments: attachments)
            if replacingUserMessageID == nil {
                currentSession.createdAt = sentAt
            }
        }
        currentSession.updatedAt = sentAt

        let userEventKind: ChatTimelineEvent.Kind = attachments.isEmpty
            ? .userMessage(text: prompt)
            : .userMessageWithAttachments(text: prompt, attachments: attachments)
        let userEvent = ChatTimelineEvent(
            id: userMessageID,
            timestamp: sentAt,
            kind: userEventKind
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
                        systemPrompt: turnSystemPrompt,
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
                        shouldKeepUserMessage: replacingUserMessageID != nil || turnProgress.hasPersistableProgress
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    @discardableResult
    func resetConversation(privacyMode: Bool = false) -> [ChatAttachment] {
        let discardedPrivateAttachments = isPrivacyModeEnabled
            ? ChatTimelineEvent.attachments(from: conversationTimeline)
            : []
        conversationTimeline = []
        currentSession = ChatSession(title: String(localized: .chatNewChat))
        isPrivacyModeEnabled = privacyMode
        return discardedPrivateAttachments
    }

    @discardableResult
    func loadConversation(session: ChatSession, events: [ChatTimelineEvent]) -> [ChatAttachment] {
        guard activeTurnID == nil else {
            return []
        }

        let discardedPrivateAttachments = isPrivacyModeEnabled
            ? ChatTimelineEvent.attachments(from: conversationTimeline)
            : []
        currentSession = session
        conversationTimeline = ChatTimelineEvent.sortedChronologically(events)
        isPrivacyModeEnabled = false
        discardUnavailableSystemPromptSelection(persistIfCleared: true)
        return discardedPrivateAttachments
    }

    private func archivedCurrentBranch(
        anchoredAt anchorUserMessageID: UUID,
        excludingRevisionID: UUID? = nil
    ) throws -> ArchivedCurrentBranch {
        let mainlineEvents = conversationTimeline.filter { event in
            if case .messageRevision = event.kind {
                return false
            }

            return true
        }
        guard let anchorIndex = mainlineEvents.firstIndex(where: { event in
            event.id == anchorUserMessageID && event.isUserMessage
        }) else {
            throw ChatRuntimeError.userMessageNotFound
        }

        let retainedRevisionEvents = conversationTimeline.filter { event in
            guard case let .messageRevision(revision) = event.kind else {
                return false
            }

            return revision.id != excludingRevisionID
        }

        return ArchivedCurrentBranch(
            prefixMainlineEvents: Array(mainlineEvents[..<anchorIndex]),
            currentBranchEvents: Array(mainlineEvents[anchorIndex...]),
            retainedRevisionEvents: retainedRevisionEvents
        )
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
        guard !isPrivacyModeEnabled else {
            NotificationCenter.default.post(
                name: Self.historyDidChangeNotification,
                object: nil
            )
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

    private func persistCurrentSessionMetadataIfNeeded() {
        guard !conversationTimeline.isEmpty else {
            return
        }

        currentSession.updatedAt = clock.now
        persistCurrentHistorySnapshot()
    }

    private func persistCurrentSessionMetadataOrDeleteEmptySession() {
        if !conversationTimeline.isEmpty {
            currentSession.updatedAt = clock.now
        }
        persistCurrentHistorySnapshot()
    }

    private func resolvedSystemPromptForNextTurn() -> SystemPromptRecord? {
        resolvedSelectedSystemPrompt(persistIfCleared: true)
    }

    private func resolvedSelectedSystemPrompt(persistIfCleared: Bool) -> SystemPromptRecord? {
        guard let promptID = currentSession.selectedSystemPromptID else {
            return nil
        }

        guard let prompt = systemPromptManager.prompt(id: promptID) else {
            currentSession.selectedSystemPromptID = nil
            if persistIfCleared {
                persistCurrentSessionMetadataOrDeleteEmptySession()
            }
            return nil
        }

        return prompt
    }

    private func discardUnavailableSystemPromptSelection(persistIfCleared: Bool) {
        guard let promptID = currentSession.selectedSystemPromptID,
              systemPromptManager.prompt(id: promptID) == nil else {
            return
        }

        currentSession.selectedSystemPromptID = nil
        if persistIfCleared {
            persistCurrentSessionMetadataOrDeleteEmptySession()
        }
    }

    private static func makeSessionTitle(
        from prompt: String,
        attachments: [ChatAttachment] = []
    ) -> String {
        let collapsedPrompt = prompt
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !collapsedPrompt.isEmpty {
            return collapsedPrompt
        }

        if let first = attachments.first {
            return first.filename.isEmpty ? String(localized: .chatAttachment) : first.filename
        }

        return String(localized: .chatNewChat)
    }

}
