//
//  ChatContextBuildPolicy.swift
//  UniLLMs
//
//  Defines which optional context inputs may degrade without failing a chat turn.
//  Created by Codex on 2026/6/5.
//

import Foundation

struct ChatContextOptionalInputFailure {
    enum Source: Equatable {
        case memories
    }

    var source: Source
    var error: Error
}

struct ChatContextBuildPolicy {
    enum MemoryRetrievalFailureBehavior: Equatable {
        case omitMemories
    }

    var memoryRetrievalFailureBehavior: MemoryRetrievalFailureBehavior
    private let optionalInputDidFail: (ChatContextOptionalInputFailure) -> Void

    init(
        memoryRetrievalFailureBehavior: MemoryRetrievalFailureBehavior = .omitMemories,
        optionalInputDidFail: @escaping (ChatContextOptionalInputFailure) -> Void = { _ in }
    ) {
        self.memoryRetrievalFailureBehavior = memoryRetrievalFailureBehavior
        self.optionalInputDidFail = optionalInputDidFail
    }

    func retrieveMemories(
        using memoryManager: MemoryManager,
        for context: ChatContext
    ) async -> [MemoryRecord] {
        do {
            return try await memoryManager.retrieveRelevantMemories(for: context)
        } catch {
            optionalInputDidFail(
                ChatContextOptionalInputFailure(
                    source: .memories,
                    error: error
                )
            )
            return memoriesAfterRetrievalFailure()
        }
    }

    private func memoriesAfterRetrievalFailure() -> [MemoryRecord] {
        switch memoryRetrievalFailureBehavior {
        case .omitMemories:
            return []
        }
    }
}
