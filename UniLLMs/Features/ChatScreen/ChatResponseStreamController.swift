//
//  ChatResponseStreamController.swift
//  UniLLMs
//
//  Owns the lifecycle of an active assistant response stream.
//  Created by Codex on 2026/6/5.
//

import Foundation

@MainActor
final class ChatResponseStreamController {
    struct Handlers {
        var didReceiveDelta: @MainActor (ChatResponseDelta) -> Void
        var didFail: @MainActor (Error) -> Void
        var didFinish: @MainActor (Bool) -> Void
    }

    private var activeTask: Task<Void, Never>?
    private var activeContinuationTask: ChatContinuationTask?
    private var activeHandlers: Handlers?

    var isActive: Bool {
        activeTask != nil
    }

    @discardableResult
    func activate(
        responseStream: AsyncThrowingStream<ChatResponseDelta, Error>,
        continuationTask: ChatContinuationTask?,
        handlers: Handlers
    ) -> Bool {
        guard activeTask == nil else {
            return false
        }

        activeContinuationTask = continuationTask
        activeHandlers = handlers
        activeContinuationTask?.onExpiration = { @MainActor [weak self] in
            self?.cancel()
        }

        activeTask = Task { [weak self] in
            do {
                for try await delta in responseStream {
                    try Task.checkCancellation()

                    await MainActor.run {
                        self?.receive(delta: delta, handlers: handlers)
                    }
                }

                await MainActor.run {
                    self?.finish(success: true, handlers: handlers)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.finish(success: false, handlers: handlers)
                }
            } catch {
                await MainActor.run {
                    handlers.didFail(error)
                    self?.finish(success: false, handlers: handlers)
                }
            }
        }

        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard let activeTask,
              let activeHandlers else {
            return false
        }

        activeTask.cancel()
        finish(success: false, handlers: activeHandlers)
        return true
    }

    func report(delta: ChatResponseDelta) {
        activeContinuationTask?.report(delta: delta)
    }

    private func receive(
        delta: ChatResponseDelta,
        handlers: Handlers
    ) {
        guard activeTask != nil else {
            return
        }

        handlers.didReceiveDelta(delta)
    }

    private func finish(
        success: Bool,
        handlers: Handlers
    ) {
        guard activeTask != nil else {
            return
        }

        activeContinuationTask?.finish(success: success)
        activeContinuationTask = nil
        activeTask = nil
        activeHandlers = nil
        handlers.didFinish(success)
    }
}
