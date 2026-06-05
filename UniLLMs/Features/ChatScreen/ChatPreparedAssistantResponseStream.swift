//
//  ChatPreparedAssistantResponseStream.swift
//  UniLLMs
//
//  Bundles a started assistant response stream with its background continuation task.
//  Created by Codex on 2026/6/5.
//

struct ChatPreparedAssistantResponseStream {
    var responseStream: AsyncThrowingStream<ChatResponseDelta, Error>
    var continuationTask: ChatContinuationTask?
}
