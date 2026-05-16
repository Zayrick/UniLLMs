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
    var displayName: String?

    var presentationName: String {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedDisplayName.isEmpty ? toolID : trimmedDisplayName
    }

    init(
        id: String,
        toolID: String,
        arguments: String,
        displayName: String? = nil
    ) {
        self.id = id
        self.toolID = toolID
        self.arguments = arguments
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case toolID
        case arguments
        case displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        toolID = try container.decode(String.self, forKey: .toolID)
        arguments = try container.decode(String.self, forKey: .arguments)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(toolID, forKey: .toolID)
        try container.encode(arguments, forKey: .arguments)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }
}

nonisolated struct ChatMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var role: ChatRole
    var content: String
    var reasoning: String
    var toolCalls: [ChatToolCall]?
    var toolCallID: String?
    var toolDisplayName: String?
    var displayParts: [ChatResponseDisplayPart]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        reasoning: String = "",
        toolCalls: [ChatToolCall]? = nil,
        toolCallID: String? = nil,
        toolDisplayName: String? = nil,
        displayParts: [ChatResponseDisplayPart] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolDisplayName = toolDisplayName
        self.displayParts = displayParts
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case reasoning
        case toolCalls
        case toolCallID
        case toolDisplayName
        case displayParts
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
        toolDisplayName = try container.decodeIfPresent(String.self, forKey: .toolDisplayName)
        displayParts = try container.decodeIfPresent([ChatResponseDisplayPart].self, forKey: .displayParts) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try container.encodeIfPresent(toolDisplayName, forKey: .toolDisplayName)
        if !displayParts.isEmpty {
            try container.encode(displayParts, forKey: .displayParts)
        }
        try container.encode(createdAt, forKey: .createdAt)
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

nonisolated enum ChatToolDisplayEvent: Codable, Equatable {
    case started(callID: String, toolID: String, displayName: String)
    case completed(callID: String, toolID: String, displayName: String)
    case failed(callID: String, toolID: String, displayName: String, message: String)

    var callID: String {
        switch self {
        case let .started(callID, _, _),
             let .completed(callID, _, _),
             let .failed(callID, _, _, _):
            return callID
        }
    }

    private enum Kind: String, Codable {
        case started
        case completed
        case failed
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case callID
        case toolID
        case displayName
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let callID = try container.decode(String.self, forKey: .callID)
        let toolID = try container.decode(String.self, forKey: .toolID)
        let displayName = try container.decode(String.self, forKey: .displayName)

        switch kind {
        case .started:
            self = .started(callID: callID, toolID: toolID, displayName: displayName)
        case .completed:
            self = .completed(callID: callID, toolID: toolID, displayName: displayName)
        case .failed:
            self = .failed(
                callID: callID,
                toolID: toolID,
                displayName: displayName,
                message: try container.decodeIfPresent(String.self, forKey: .message) ?? ""
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .started(callID, toolID, displayName):
            try container.encode(Kind.started, forKey: .kind)
            try container.encode(callID, forKey: .callID)
            try container.encode(toolID, forKey: .toolID)
            try container.encode(displayName, forKey: .displayName)
        case let .completed(callID, toolID, displayName):
            try container.encode(Kind.completed, forKey: .kind)
            try container.encode(callID, forKey: .callID)
            try container.encode(toolID, forKey: .toolID)
            try container.encode(displayName, forKey: .displayName)
        case let .failed(callID, toolID, displayName, message):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(callID, forKey: .callID)
            try container.encode(toolID, forKey: .toolID)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(message, forKey: .message)
        }
    }
}

/// Ordered display events for one streamed delta. Keeping this separate from
/// persisted text mirrors VS Code's response-part stream and prevents later
/// reasoning/tool UI from being folded back into the first thinking block.
nonisolated enum ChatResponseDisplayPart: Codable, Equatable {
    case reasoning(String)
    case content(String)
    case toolEvent(ChatToolDisplayEvent)

    var isEmpty: Bool {
        switch self {
        case let .reasoning(text),
             let .content(text):
            return text.isEmpty
        case .toolEvent(_):
            return false
        }
    }

    private enum Kind: String, Codable {
        case reasoning
        case content
        case toolEvent
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case toolEvent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .reasoning:
            self = .reasoning(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case .content:
            self = .content(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case .toolEvent:
            self = .toolEvent(try container.decode(ChatToolDisplayEvent.self, forKey: .toolEvent))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .reasoning(text):
            try container.encode(Kind.reasoning, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .content(text):
            try container.encode(Kind.content, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .toolEvent(event):
            try container.encode(Kind.toolEvent, forKey: .kind)
            try container.encode(event, forKey: .toolEvent)
        }
    }
}

nonisolated struct ChatResponseDelta: Equatable {
    var content: String
    var reasoning: String
    var toolCalls: [ChatToolCall]
    var displayParts: [ChatResponseDisplayPart]

    init(
        content: String = "",
        reasoning: String = "",
        toolCalls: [ChatToolCall] = [],
        displayParts: [ChatResponseDisplayPart]? = nil
    ) {
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.displayParts = (displayParts ?? Self.makeDisplayParts(
            content: content,
            reasoning: reasoning
        ))
        .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        content.isEmpty
            && reasoning.isEmpty
            && toolCalls.isEmpty
            && displayParts.isEmpty
    }

    private static func makeDisplayParts(
        content: String,
        reasoning: String
    ) -> [ChatResponseDisplayPart] {
        var parts: [ChatResponseDisplayPart] = []
        if !reasoning.isEmpty {
            parts.append(.reasoning(reasoning))
        }
        if !content.isEmpty {
            parts.append(.content(content))
        }
        return parts
    }
}

nonisolated enum ChatTurnEvent: Equatable {
    case displayDelta(ChatResponseDelta)
    case transcriptMessage(ChatMessage)
}

typealias LLMModelSelection = ChatModelSelection
