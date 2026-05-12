//
//  FakeLLMsProvider.swift
//  UniLLMs
//
//  Provides a no-configuration fake LLM provider with deterministic static and streaming models.
//  Created by Codex on 2026/5/12.
//

import Foundation

nonisolated extension LLMsProviderKind {
    static let fake = LLMsProviderKind(rawValue: "fake")
}

struct FakeLLMsProvider: LLMsProviderAdapter {
    private enum Metadata {
        static let displayName = "Fake"
        static let staticResponse = "This is a fake static response returned after a short delay."
        static let streamResponse = "This is a fake streaming response. It arrives gradually so the streaming UI can be checked without a real provider."
        static let streamInitialDelayNanoseconds: UInt64 = 2_000_000_000
        static let streamCharacterDelayNanoseconds: UInt64 = 100_000_000
        static let staticResponseDelayNanoseconds: UInt64 = 3_000_000_000
    }

    enum ModelID {
        static let staticResponse = "static"
        static let stream = "stream"
    }

    private let staticResponseDelayNanoseconds: UInt64
    private let streamInitialDelayNanoseconds: UInt64
    private let streamCharacterDelayNanoseconds: UInt64

    init(
        staticResponseDelayNanoseconds: UInt64 = Metadata.staticResponseDelayNanoseconds,
        streamInitialDelayNanoseconds: UInt64 = Metadata.streamInitialDelayNanoseconds,
        streamCharacterDelayNanoseconds: UInt64 = Metadata.streamCharacterDelayNanoseconds
    ) {
        self.staticResponseDelayNanoseconds = staticResponseDelayNanoseconds
        self.streamInitialDelayNanoseconds = streamInitialDelayNanoseconds
        self.streamCharacterDelayNanoseconds = streamCharacterDelayNanoseconds
    }

    var kind: LLMsProviderKind {
        .fake
    }

    var displayName: String {
        Metadata.displayName
    }

    var capabilities: Set<LLMsProviderCapability> {
        [.modelList, .streamingChat]
    }

    var defaultConfiguration: LLMsProviderConfiguration {
        LLMsProviderConfiguration()
    }

    var configurationFields: [LLMsProviderConfigurationField] {
        []
    }

    var modelSource: LLMsProviderModelSource {
        .`static`
    }

    var staticModels: [LLMsProviderModel] {
        [
            LLMsProviderModel(id: ModelID.staticResponse, name: "Static"),
            LLMsProviderModel(id: ModelID.stream, name: "Stream")
        ]
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch request.modelID {
                    case ModelID.staticResponse:
                        try await Task.sleep(nanoseconds: staticResponseDelayNanoseconds)
                        try Task.checkCancellation()
                        continuation.yield(ChatResponseDelta(content: Metadata.staticResponse))
                    case ModelID.stream:
                        try await Task.sleep(nanoseconds: streamInitialDelayNanoseconds)
                        try await streamResponse(Metadata.streamResponse, into: continuation)
                    default:
                        throw FakeLLMsProviderError.unsupportedModel(request.modelID)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamResponse(
        _ response: String,
        into continuation: AsyncThrowingStream<ChatResponseDelta, Error>.Continuation
    ) async throws {
        for character in response {
            try Task.checkCancellation()
            continuation.yield(ChatResponseDelta(content: String(character)))
            try await Task.sleep(nanoseconds: streamCharacterDelayNanoseconds)
        }
    }
}

enum FakeLLMsProviderError: LocalizedError, Equatable {
    case unsupportedModel(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedModel(modelID):
            return "Fake provider does not support model: \(modelID)"
        }
    }
}
