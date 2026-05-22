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
    var attachments: [ChatAttachment]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        reasoning: String = "",
        toolCalls: [ChatToolCall]? = nil,
        toolCallID: String? = nil,
        toolDisplayName: String? = nil,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolDisplayName = toolDisplayName
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

nonisolated struct ChatAttachment: Codable, Equatable, Identifiable {
    nonisolated enum Kind: String, Codable, Equatable {
        case image
        case file
    }

    /// Stable ID of this attachment instance inside a message.
    var id: UUID
    /// Stable ID of the on-disk file asset referenced by this attachment.
    var assetID: UUID
    var kind: Kind
    var filename: String
    var contentType: String
    /// File name stored relative to `ChatAttachmentStore`'s root directory.
    var relativePath: String

    init(
        id: UUID = UUID(),
        assetID: UUID = UUID(),
        kind: Kind,
        filename: String,
        contentType: String,
        relativePath: String
    ) {
        self.id = id
        self.assetID = assetID
        self.kind = kind
        self.filename = filename
        self.contentType = contentType
        self.relativePath = relativePath
    }
}

nonisolated struct ChatSession: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var selectedSystemPromptID: UUID?

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        selectedSystemPromptID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.selectedSystemPromptID = selectedSystemPromptID
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
    var systemPrompt: SystemPromptRecord?
    var memories: [MemoryRecord]
    var availableTools: [ToolDefinition]

    init(
        session: ChatSession? = nil,
        messages: [ChatMessage] = [],
        systemPrompt: SystemPromptRecord? = nil,
        memories: [MemoryRecord] = [],
        availableTools: [ToolDefinition] = []
    ) {
        self.session = session
        self.messages = messages
        self.systemPrompt = systemPrompt
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

/// Shared tool invocation event used by streaming UI and persisted timeline entries.
nonisolated enum ChatToolEvent: Codable, Equatable {
    case started(ChatToolCall)
    case completed(ChatToolCall, result: String)
    case failed(ChatToolCall, message: String)
}

nonisolated extension ChatToolEvent {
    var providerMessageContent: String {
        switch self {
        case .started:
            return ""
        case let .completed(_, result):
            return result
        case let .failed(_, message):
            return "Tool execution failed: \(message)"
        }
    }
}

/// Ordered display events for one streamed delta. This is transient UI state;
/// persisted history is represented by `ChatTimelineEvent`.
nonisolated enum ChatResponseDisplayPart: Equatable {
    case reasoning(String)
    case content(String)
    case toolEvent(ChatToolEvent)

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
