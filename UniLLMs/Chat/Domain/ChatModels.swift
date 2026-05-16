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

nonisolated struct ChatMessage: Equatable, Identifiable {
    var id: UUID
    var role: ChatRole
    var content: String
    var reasoning: String
    var toolCalls: [ChatToolCall]?
    var toolCallID: String?
    var toolDisplayName: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        reasoning: String = "",
        toolCalls: [ChatToolCall]? = nil,
        toolCallID: String? = nil,
        toolDisplayName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolDisplayName = toolDisplayName
        self.createdAt = createdAt
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

nonisolated enum ChatToolDisplayEvent: Equatable {
    case started(callID: String, toolID: String, displayName: String, arguments: String)
    case completed(callID: String, toolID: String, displayName: String, result: String)
    case failed(callID: String, toolID: String, displayName: String, message: String)

    var callID: String {
        switch self {
        case let .started(callID, _, _, _),
             let .completed(callID, _, _, _),
             let .failed(callID, _, _, _):
            return callID
        }
    }
}

/// Ordered display events for one streamed delta. This is transient UI state;
/// persisted history is represented by `ChatTimelineEvent`.
nonisolated enum ChatResponseDisplayPart: Equatable {
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
    case timelineEvent(ChatTimelineEvent.Kind)
}

typealias LLMModelSelection = ChatModelSelection
