//
//  ChatMarkdownPendingBuffer.swift
//  UniLLMs
//
//  Buffers streamed Markdown chunks between display-link flushes.
//

import Foundation

struct ChatMarkdownPendingBuffer {
    private var chunks: [String] = []
    private var chunkIndex = 0
    private var chunkStartIndex: String.Index?

    var hasPendingMarkdown: Bool {
        currentChunk != nil
    }

    mutating func append(_ chunk: String) {
        guard !chunk.isEmpty else {
            return
        }

        chunks.append(chunk)
    }

    mutating func nextChunk(maxCharacters: Int) -> String {
        guard maxCharacters > 0 else {
            return ""
        }

        var result = ""
        while result.count < maxCharacters,
              let chunk = currentChunk {
            let start = chunkStartIndex ?? chunk.startIndex
            let remainingBudget = maxCharacters - result.count
            if let end = chunk.index(
                start,
                offsetBy: remainingBudget,
                limitedBy: chunk.endIndex
            ) {
                result += String(chunk[start..<end])
                if end == chunk.endIndex {
                    advanceChunk()
                } else {
                    chunkStartIndex = end
                }
                break
            }

            result += String(chunk[start...])
            advanceChunk()
        }

        compactConsumedChunksIfNeeded()
        return result
    }

    mutating func drain() -> String {
        var remainingChunks: [String] = []
        while let chunk = currentChunk {
            let start = chunkStartIndex ?? chunk.startIndex
            remainingChunks.append(String(chunk[start...]))
            advanceChunk()
        }

        clear()
        return remainingChunks.joined()
    }

    mutating func clear() {
        chunks.removeAll(keepingCapacity: true)
        chunkIndex = 0
        chunkStartIndex = nil
    }

    private var currentChunk: String? {
        guard chunkIndex < chunks.count else {
            return nil
        }

        let chunk = chunks[chunkIndex]
        let start = chunkStartIndex ?? chunk.startIndex
        return start < chunk.endIndex ? chunk : nil
    }

    private mutating func advanceChunk() {
        chunkIndex += 1
        chunkStartIndex = nil
    }

    private mutating func compactConsumedChunksIfNeeded() {
        if chunkIndex == chunks.count {
            chunks.removeAll(keepingCapacity: true)
            chunkIndex = 0
        } else if chunkIndex > 64 {
            chunks.removeFirst(chunkIndex)
            chunkIndex = 0
        }
    }
}
