//
//  ChatModels.swift
//  UniLLMs
//
//  Defines chat sessions, messages, context, model selection, requests, and streaming response domain models.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated enum ChatRole: String, Codable, Equatable {
    case user
    case assistant
    case system
    case tool
}

nonisolated struct ChatToolCall: Codable, Equatable, Identifiable {
    var id: String
    var toolID: String
    var arguments: String
}

nonisolated struct ChatMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var role: ChatRole
    var content: String
    var reasoning: String
    var toolCalls: [ChatToolCall]?
    var toolCallID: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        reasoning: String = "",
        toolCalls: [ChatToolCall]? = nil,
        toolCallID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case reasoning
        case toolCalls
        case toolCallID
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        toolCalls = try container.decodeIfPresent([ChatToolCall].self, forKey: .toolCalls)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    static func sortedChronologically(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.enumerated()
            .sorted {
                if $0.element.createdAt != $1.element.createdAt {
                    return $0.element.createdAt < $1.element.createdAt
                }

                return $0.offset < $1.offset
            }
            .map(\.element)
    }
}

nonisolated struct ChatAttachment: Codable, Equatable, Identifiable {
    var id: UUID
    var filename: String
    var contentType: String
    var localURL: URL?

    init(
        id: UUID = UUID(),
        filename: String,
        contentType: String,
        localURL: URL? = nil
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.localURL = localURL
    }
}

nonisolated struct ChatSession: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct ChatModelSelection: Equatable {
    var providerID: UUID
    var providerName: String
    var modelID: String
    var modelName: String?

    var displayName: String {
        let trimmedModelName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedModelName.isEmpty ? modelID : trimmedModelName
    }
}

nonisolated struct ChatContext: Equatable {
    var session: ChatSession?
    var messages: [ChatMessage]
    var memories: [MemoryRecord]
    var availableTools: [ToolDefinition]

    init(
        session: ChatSession? = nil,
        messages: [ChatMessage] = [],
        memories: [MemoryRecord] = [],
        availableTools: [ToolDefinition] = []
    ) {
        self.session = session
        self.messages = messages
        self.memories = memories
        self.availableTools = availableTools
    }
}

nonisolated struct ChatRequest: Equatable {
    var modelID: String
    var messages: [ChatMessage]
    var context: ChatContext
}

nonisolated struct ChatResponse: Equatable {
    var message: ChatMessage
}

nonisolated struct ChatResponseDelta: Equatable {
    var content: String = ""
    var reasoning: String = ""
    var toolCalls: [ChatToolCall] = []
    var toolStatus: String = ""

    var isEmpty: Bool {
        content.isEmpty && reasoning.isEmpty && toolCalls.isEmpty && toolStatus.isEmpty
    }
}

nonisolated enum ChatTurnEvent: Equatable {
    case displayDelta(ChatResponseDelta)
    case transcriptMessage(ChatMessage)
}

typealias LLMModelSelection = ChatModelSelection
