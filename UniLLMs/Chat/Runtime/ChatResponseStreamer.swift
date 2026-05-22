//
//  ChatResponseStreamer.swift
//  UniLLMs
//
//  Creates provider response streams so ChatTurnRunner does not depend directly on provider management details.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class ChatResponseStreamer {
    private let providerManager: LLMsProviderManager

    init(providerManager: LLMsProviderManager) {
        self.providerManager = providerManager
    }

    func streamResponse(
        provider: LLMsProviderRecord,
        modelID: String,
        messages: [ChatMessage],
        context: ChatContext
    ) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
        try providerManager.streamChat(
            provider: provider,
            modelID: modelID,
            messages: messages,
            context: context
        )
    }
}
