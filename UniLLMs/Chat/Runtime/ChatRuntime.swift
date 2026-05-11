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
    private let providerStore: LLMsProviderStore
    private let contextBuilder: ChatContextBuilder
    private let turnRunner: ChatTurnRunner
    private var currentSession = ChatSession(title: "New Chat")
    private var conversationMessages: [ChatMessage] = []
    private var activeTurnID: UUID?

    init(
        providerStore: LLMsProviderStore,
        contextBuilder: ChatContextBuilder,
        turnRunner: ChatTurnRunner
    ) {
        self.providerStore = providerStore
        self.contextBuilder = contextBuilder
        self.turnRunner = turnRunner
    }

    func startTurn(prompt: String) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
        guard activeTurnID == nil else {
            throw ChatRuntimeError.turnAlreadyInProgress
        }

        guard let selection = providerStore.fetchSelectedModelSelection() else {
            throw ChatRuntimeError.missingModelSelection
        }

        guard let provider = providerStore.fetchProvider(id: selection.providerID) else {
            throw ChatRuntimeError.selectedProviderUnavailable
        }

        let turnID = UUID()
        let userMessage = ChatMessage(role: .user, content: prompt)
        let requestMessages = conversationMessages + [userMessage]
        conversationMessages.append(userMessage)
        activeTurnID = turnID

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

        currentSession.updatedAt = Date()
        activeTurnID = nil
    }
}
