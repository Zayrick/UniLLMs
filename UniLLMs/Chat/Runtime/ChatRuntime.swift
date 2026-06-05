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

    private let providerStore: LLMsProviderStore
    private let providerManager: LLMsProviderManager
    private let systemPromptManager: SystemPromptManager
    private let contextBuilder: ChatContextBuilder
    private let turnRunner: ChatTurnRunner
    private let historyPersistenceFailureSink: ChatHistoryPersistenceFailureSink
    private let historyPersistence: ChatHistoryPersistenceQueue
    private let clock: any AppClock
    private var currentSession: ChatSession
    private var conversationTimeline: [ChatTimelineEvent] = []
    private var activeTurnID: UUID?
    private(set) var isPrivacyModeEnabled = false

    init(
        providerStore: LLMsProviderStore,
        providerManager: LLMsProviderManager,
        systemPromptManager: SystemPromptManager = SystemPromptManager(),
        contextBuilder: ChatContextBuilder,
        turnRunner: ChatTurnRunner,
        historyStore: (any ChatHistoryStore)? = nil,
        historyPersistenceDidFail: @escaping @MainActor (Error) -> Void = { _ in },
        clock: any AppClock = SystemAppClock()
    ) {
        self.providerStore = providerStore
        self.providerManager = providerManager
        self.systemPromptManager = systemPromptManager
        self.contextBuilder = contextBuilder
        self.turnRunner = turnRunner
        let historyPersistenceFailureSink = ChatHistoryPersistenceFailureSink(
            handler: historyPersistenceDidFail
        )
        self.historyPersistenceFailureSink = historyPersistenceFailureSink
        self.historyPersistence = ChatHistoryPersistenceQueue(
            historyStore: historyStore,
            notificationName: Self.historyDidChangeNotification
        ) { error in
            historyPersistenceFailureSink.report(error)
        }
        self.clock = clock
        let now = clock.now
        currentSession = ChatSession(
            title: String(localized: .chatNewChat),
            createdAt: now,
            updatedAt: now
        )
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
        await historyPersistence.waitForPendingPersistence()
    }

    @MainActor
    func setHistoryPersistenceFailureHandler(_ handler: @escaping @MainActor (Error) -> Void) {
        historyPersistenceFailureSink.handler = handler
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

        let switchedAt = clock.now
        let switchPlan = ChatRevisionSwitchPlan(
            anchorUserMessageID: anchorUserMessageID,
            revisionID: revisionID,
            switchedAt: switchedAt
        )
        guard let result = switchPlan.apply(to: conversationTimeline) else {
            throw ChatRuntimeError.userMessageNotFound
        }

        conversationTimeline = result.timeline
        currentSession.updatedAt = result.sessionUpdatedAt
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
        let startPlan = ChatTurnStartPlan(
            prompt: prompt,
            attachments: attachments,
            userMessageID: userMessageID,
            replacingUserMessageID: replacingUserMessageID,
            sentAt: sentAt,
            emptyConversationTitle: String(localized: .chatNewChat),
            attachmentFallbackTitle: String(localized: .chatAttachment)
        )
        guard let startResult = startPlan.apply(
            to: currentSession,
            timeline: conversationTimeline
        ) else {
            throw ChatRuntimeError.userMessageNotFound
        }

        currentSession = startResult.session
        conversationTimeline = startResult.timeline
        let turnSystemPrompt = resolvedSystemPromptForNextTurn()
        activeTurnID = turnID
        persistCurrentHistorySnapshot()

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                var turnProgress = ChatTurnProgress()

                do {
                    guard let self else {
                        continuation.finish()
                        return
                    }
                    turnProgress = ChatTurnProgress(clock: self.clock)

                    let context = await self.contextBuilder.buildContext(
                        session: self.currentSession,
                        messages: startResult.requestMessages,
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
                            turnProgress.append(displayDelta: delta)
                            continuation.yield(delta)
                        case let .timelineEvent(kind):
                            turnProgress.append(timelineEvent: kind)
                        }
                    }

                    self.finishTurn(
                        id: turnID,
                        userEventID: startResult.userEvent.id,
                        progress: turnProgress,
                        shouldKeepUserMessage: true
                    )
                    continuation.finish()
                } catch is CancellationError {
                    self?.finishTurn(
                        id: turnID,
                        userEventID: startResult.userEvent.id,
                        progress: turnProgress,
                        shouldKeepUserMessage: true
                    )
                    continuation.finish()
                } catch {
                    self?.finishTurn(
                        id: turnID,
                        userEventID: startResult.userEvent.id,
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
        let transition = ChatConversationTransitionPlan.reset(
            currentTimeline: conversationTimeline,
            wasPrivacyModeEnabled: isPrivacyModeEnabled,
            privacyMode: privacyMode,
            now: clock.now,
            emptyConversationTitle: String(localized: .chatNewChat)
        )
        currentSession = transition.session
        conversationTimeline = transition.timeline
        isPrivacyModeEnabled = transition.privacyModeEnabled
        return transition.discardedPrivateAttachments
    }

    @discardableResult
    func loadConversation(session: ChatSession, events: [ChatTimelineEvent]) -> [ChatAttachment] {
        guard activeTurnID == nil else {
            return []
        }

        let transition = ChatConversationTransitionPlan.load(
            session: session,
            events: events,
            currentTimeline: conversationTimeline,
            wasPrivacyModeEnabled: isPrivacyModeEnabled
        )
        currentSession = transition.session
        conversationTimeline = transition.timeline
        isPrivacyModeEnabled = transition.privacyModeEnabled
        discardUnavailableSystemPromptSelection(persistIfCleared: true)
        return transition.discardedPrivateAttachments
    }

    private func finishTurn(
        id turnID: UUID,
        userEventID: UUID,
        progress: ChatTurnProgress,
        shouldKeepUserMessage: Bool
    ) {
        let completionPlan = ChatTurnCompletionPlan(
            turnID: turnID,
            activeTurnID: activeTurnID,
            userEventID: userEventID,
            progressEvents: progress.finishedEvents(),
            shouldKeepUserMessage: shouldKeepUserMessage
        )
        guard let result = completionPlan.apply(
            to: conversationTimeline,
            sessionUpdatedAt: currentSession.updatedAt
        ) else {
            return
        }

        conversationTimeline = result.timeline
        currentSession.updatedAt = result.sessionUpdatedAt
        activeTurnID = nil
        persistCurrentHistorySnapshot()
    }

    private func persistCurrentHistorySnapshot() {
        historyPersistence.persist(
            session: currentSession,
            events: conversationTimeline,
            privacyModeEnabled: isPrivacyModeEnabled
        )
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

}

private final class ChatHistoryPersistenceFailureSink {
    var handler: @MainActor (Error) -> Void

    init(handler: @escaping @MainActor (Error) -> Void) {
        self.handler = handler
    }

    @MainActor
    func report(_ error: Error) {
        handler(error)
    }
}
