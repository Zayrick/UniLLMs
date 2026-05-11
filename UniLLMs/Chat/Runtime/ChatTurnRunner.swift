//
//  ChatTurnRunner.swift
//  UniLLMs
//
//  Runs a single chat turn by connecting prompt assembly to streaming response output.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class ChatTurnRunner {
    private let responseStreamer: ChatResponseStreamer
    private let promptAssembler: ChatPromptAssembler

    init(
        responseStreamer: ChatResponseStreamer,
        promptAssembler: ChatPromptAssembler = ChatPromptAssembler()
    ) {
        self.responseStreamer = responseStreamer
        self.promptAssembler = promptAssembler
    }

    func streamResponse(
        provider: LLMsProviderRecord,
        modelID: String,
        context: ChatContext
    ) throws -> AsyncThrowingStream<ChatResponseDelta, Error> {
        try responseStreamer.streamResponse(
            provider: provider,
            modelID: modelID,
            messages: promptAssembler.assembleMessages(from: context),
            context: context
        )
    }
}
