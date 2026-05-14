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

    private let providerStore: LLMsProviderStore
    private let providerManager: LLMsProviderManager
    private let contextBuilder: ChatContextBuilder
    private let turnRunner: ChatTurnRunner
    private let historyStore: (any ChatHistoryStore)?
    private var currentSession = ChatSession(title: "New Chat")
    private var conversationMessages: [ChatMessage] = []
    private var activeTurnID: UUID?
    private var historyPersistenceTask: Task<Void, Never>?

    init(
        providerStore: LLMsProviderStore,
        providerManager: LLMsProviderManager,
        contextBuilder: ChatContextBuilder,
        turnRunner: ChatTurnRunner,
        historyStore: (any ChatHistoryStore)? = nil
    ) {
        self.providerStore = providerStore
        self.providerManager = providerManager
        self.contextBuilder = contextBuilder
        self.turnRunner = turnRunner
        self.historyStore = historyStore
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
        let sentAt = Date()
        if conversationMessages.isEmpty {
            currentSession.title = Self.makeSessionTitle(from: prompt)
            currentSession.createdAt = sentAt
        }
        currentSession.updatedAt = sentAt

        let userMessage = ChatMessage(role: .user, content: prompt, createdAt: sentAt)
        let requestMessages = conversationMessages + [userMessage]
        conversationMessages.append(userMessage)
        activeTurnID = turnID
        persistCurrentHistorySnapshot()

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                var assistantContent = ""

                do {
                    guard let self else {
                        continuation.finish()
                        return
                    }

                    let context = await self.contextBuilder.buildContext(
                        session: self.currentSession,
                        messages: requestMessages
                    )
                    let stream = try self.turnRunner.streamResponse(
                        provider: provider,
                        modelID: selection.modelID,
                        context: context
                    )

                    for try await delta in stream {
                        try Task.checkCancellation()
                        assistantContent += delta.content
                        continuation.yield(delta)
                    }

                    self.finishTurn(
                        id: turnID,
                        userMessageID: userMessage.id,
                        assistantContent: assistantContent,
                        shouldKeepUserMessage: true
                    )
                    continuation.finish()
                } catch is CancellationError {
                    self?.finishTurn(
                        id: turnID,
                        userMessageID: userMessage.id,
                        assistantContent: assistantContent,
                        shouldKeepUserMessage: true
                    )
                    continuation.finish()
                } catch {
                    self?.finishTurn(
                        id: turnID,
                        userMessageID: userMessage.id,
                        assistantContent: assistantContent,
                        shouldKeepUserMessage: !assistantContent.isEmpty
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
        conversationMessages = []
        currentSession = ChatSession(title: "New Chat")
    }

    func loadConversation(session: ChatSession, messages: [ChatMessage]) {
        guard activeTurnID == nil else {
            return
        }

        currentSession = session
        conversationMessages = messages.sorted { $0.createdAt < $1.createdAt }
    }

    private func finishTurn(
        id turnID: UUID,
        userMessageID: UUID,
        assistantContent: String,
        shouldKeepUserMessage: Bool
    ) {
        guard activeTurnID == turnID else {
            return
        }

        if !assistantContent.isEmpty {
            conversationMessages.append(
                ChatMessage(role: .assistant, content: assistantContent)
            )
        } else if !shouldKeepUserMessage {
            conversationMessages.removeAll { $0.id == userMessageID }
        }

        activeTurnID = nil
        persistCurrentHistorySnapshot()
    }

    private func persistCurrentHistorySnapshot() {
        guard let historyStore else {
            return
        }

        let session = currentSession
        let messages = conversationMessages
        let previousTask = historyPersistenceTask
        historyPersistenceTask = Task { @MainActor [previousTask, historyStore] in
            if let previousTask {
                await previousTask.value
            }

            if messages.isEmpty {
                try? await historyStore.deleteSession(id: session.id)
            } else {
                try? await historyStore.saveSession(session)
                try? await historyStore.saveMessages(messages, sessionID: session.id)
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
