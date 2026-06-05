//
//  ChatHistoryWorkflowController.swift
//  UniLLMs
//
//  Owns asynchronous chat history list, selection, and deletion workflows.
//  Created by Codex on 2026/6/5.
//

import Foundation

@MainActor
final class ChatHistoryWorkflowController {
    @MainActor
    private final class ActionTaskSlot {
        struct Token: Equatable {
            fileprivate let id: Int
        }

        private var nextTokenID = 0
        private var activeToken: Token?
        private var task: Task<Void, Never>?
        private var didCancel: (@MainActor () -> Void)?

        func cancel() {
            guard activeToken != nil else {
                return
            }

            let cancellation = didCancel
            let task = task
            clear()
            task?.cancel()
            cancellation?()
        }

        func finish(_ token: Token) {
            guard activeToken == token else {
                return
            }

            clear()
        }

        func replace(
            didCancel: @escaping @MainActor () -> Void,
            makeTask: (Token) -> Task<Void, Never>
        ) {
            cancel()
            nextTokenID += 1
            let token = Token(id: nextTokenID)
            activeToken = token
            self.didCancel = didCancel
            task = makeTask(token)
        }

        private func clear() {
            didCancel = nil
            task = nil
            activeToken = nil
        }
    }

    private let historyStore: any ChatHistoryStore
    private var reloadTask: Task<Void, Never>?
    private let actionTaskSlot = ActionTaskSlot()

    init(historyStore: any ChatHistoryStore) {
        self.historyStore = historyStore
    }

    func cancel() {
        reloadTask?.cancel()
        reloadTask = nil
        actionTaskSlot.cancel()
    }

    func reloadSessions(
        selectedSessionID: UUID?,
        didReload: @escaping @MainActor ([ChatSession], UUID?) -> Void,
        didFail: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        reloadTask?.cancel()
        reloadTask = Task { [historyStore] in
            do {
                let sessions = try await historyStore.fetchSessions()
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    didReload(sessions, selectedSessionID)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    didFail(error)
                }
            }
        }
    }

    @discardableResult
    func selectSession(
        _ session: ChatSession,
        isResponseActive: @escaping @MainActor () -> Bool,
        didLoad: @escaping @MainActor (ChatSession, [ChatTimelineEvent]) -> Void,
        didReject: @escaping @MainActor () -> Void = {},
        didFail: @escaping @MainActor (Error) -> Void = { _ in }
    ) -> Bool {
        guard ChatHistoryActionPolicy.selectionDecision(
            isResponseActive: isResponseActive()
        ) == .load else {
            didReject()
            return false
        }

        let actionTaskSlot = actionTaskSlot
        actionTaskSlot.replace(didCancel: didReject) { token in
            Task { [historyStore, actionTaskSlot] in
                do {
                    let events = try await historyStore.fetchEvents(sessionID: session.id)
                    guard !Task.isCancelled else {
                        return
                    }

                    let shouldLoad = await MainActor.run {
                        ChatHistoryActionPolicy.selectionDecision(
                            isResponseActive: isResponseActive()
                        ) == .load
                    }
                    guard shouldLoad else {
                        await MainActor.run {
                            actionTaskSlot.finish(token)
                            didReject()
                        }
                        return
                    }

                    await MainActor.run {
                        actionTaskSlot.finish(token)
                        didLoad(session, events)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        actionTaskSlot.finish(token)
                    }
                    return
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        actionTaskSlot.finish(token)
                        didFail(error)
                    }
                }
            }
        }
        return true
    }

    @discardableResult
    func deleteSession(
        _ session: ChatSession,
        currentSessionID: UUID,
        isResponseActive: @escaping @MainActor () -> Bool,
        currentSessionIDProvider: @escaping @MainActor () -> UUID,
        didDelete: @escaping @MainActor (ChatHistoryActionPolicy.DeletionDecision) -> Void,
        didReject: @escaping @MainActor () -> Void = {},
        didFail: @escaping @MainActor (Error) -> Void = { _ in }
    ) -> Bool {
        guard ChatHistoryActionPolicy.deletionDecision(
            sessionID: session.id,
            currentSessionID: currentSessionID,
            isResponseActive: isResponseActive()
        ) != .ignore else {
            didReject()
            return false
        }

        let actionTaskSlot = actionTaskSlot
        actionTaskSlot.replace(didCancel: didReject) { token in
            Task { [historyStore, actionTaskSlot] in
                do {
                    let shouldDelete = await MainActor.run {
                        ChatHistoryActionPolicy.deletionDecision(
                            sessionID: session.id,
                            currentSessionID: currentSessionIDProvider(),
                            isResponseActive: isResponseActive()
                        ) != .ignore
                    }
                    guard shouldDelete else {
                        await MainActor.run {
                            actionTaskSlot.finish(token)
                            didReject()
                        }
                        return
                    }

                    try await historyStore.deleteSession(id: session.id)
                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        let completionDecision = ChatHistoryActionPolicy.deletionCompletionDecision(
                            sessionID: session.id,
                            currentSessionID: currentSessionIDProvider(),
                            isResponseActive: isResponseActive()
                        )
                        actionTaskSlot.finish(token)
                        didDelete(completionDecision)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        actionTaskSlot.finish(token)
                    }
                    return
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        actionTaskSlot.finish(token)
                        didFail(error)
                    }
                }
            }
        }
        return true
    }
}
