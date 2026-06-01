//
//  MemoryTools.swift
//  UniLLMs
//
//  Built-in tools that let a model manage the user's saved memories.
//  Created by Codex on 2026/6/1.
//

import Foundation

nonisolated struct MemoryToolUserFacingItem: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var symbolName: String
}

nonisolated enum MemoryToolCatalog {
    static let addID = "memory_add"
    static let deleteID = "memory_delete"
    static let listID = "memory_list"
    static let searchID = "memory_search"
    static let updateID = "memory_update"

    static let userFacingItems = [
        MemoryToolUserFacingItem(
            id: addID,
            title: "Save memories",
            subtitle: "Let the assistant save details you ask it to remember.",
            symbolName: "plus.circle"
        ),
        MemoryToolUserFacingItem(
            id: searchID,
            title: "Find memories",
            subtitle: "Let the assistant look up saved details when they may help.",
            symbolName: "magnifyingglass"
        ),
        MemoryToolUserFacingItem(
            id: listID,
            title: "View memories",
            subtitle: "Let the assistant see saved memories and their IDs.",
            symbolName: "list.bullet"
        ),
        MemoryToolUserFacingItem(
            id: updateID,
            title: "Update memories",
            subtitle: "Let the assistant revise a saved memory when you ask.",
            symbolName: "pencil"
        ),
        MemoryToolUserFacingItem(
            id: deleteID,
            title: "Delete memories",
            subtitle: "Let the assistant remove a saved memory when you ask.",
            symbolName: "trash"
        )
    ]

    static var toolIDs: [String] {
        userFacingItems.map(\.id)
    }

    static func containsTool(id: String) -> Bool {
        toolIDs.contains(id)
    }
}

struct MemoryAddTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.addID,
        displayName: "Save Memory",
        summary: "Save a detail the user wants the assistant to remember.",
        symbolName: "plus.circle",
        parameters: MemoryToolSchemas.addMemory
    )

    private let memoryManager: MemoryManager

    init(memoryManager: MemoryManager) {
        self.memoryManager = memoryManager
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = MemoryToolArguments(call.arguments)
            let text = try arguments.requiredTrimmedString("text")
            let now = Date()
            let memory = MemoryRecord(
                scope: .user,
                text: text,
                createdAt: now,
                updatedAt: now
            )

            try await memoryManager.saveMemory(memory)
            return ToolResult(
                callID: call.id,
                content: MemoryToolFormatter.encodedAdd(memory: memory)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemoryDeleteTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.deleteID,
        displayName: "Delete Memory",
        summary: "Delete a saved memory when the user asks.",
        symbolName: "trash",
        parameters: MemoryToolSchemas.deleteMemory
    )

    private let memoryManager: MemoryManager

    init(memoryManager: MemoryManager) {
        self.memoryManager = memoryManager
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = MemoryToolArguments(call.arguments)
            let id = try arguments.requiredUUID("id")
            let didDelete = try await memoryManager.deleteMemory(id: id)
            guard didDelete else {
                return ToolResult(
                    callID: call.id,
                    content: "No memory exists for id \(id.uuidString).",
                    status: .error
                )
            }

            return ToolResult(
                callID: call.id,
                content: MemoryToolFormatter.encodedDelete(id: id)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemoryListTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.listID,
        displayName: "View Memories",
        summary: "Show saved memories so the assistant can use or manage them.",
        symbolName: "list.bullet",
        parameters: MemoryToolSchemas.listMemories
    )

    private let memoryManager: MemoryManager

    init(memoryManager: MemoryManager) {
        self.memoryManager = memoryManager
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = MemoryToolArguments(call.arguments)
            let limit = arguments.optionalClampedLimit(defaultValue: 20, maximum: 100)
            let memories = try await memoryManager.searchMemories(
                query: "",
                scope: .user,
                limit: limit
            )
            return ToolResult(
                callID: call.id,
                content: MemoryToolFormatter.encodedList(memories: memories)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemorySearchTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.searchID,
        displayName: "Find Memories",
        summary: "Find saved memories that may help answer the user.",
        symbolName: "magnifyingglass",
        parameters: MemoryToolSchemas.searchMemories
    )

    private let memoryManager: MemoryManager

    init(memoryManager: MemoryManager) {
        self.memoryManager = memoryManager
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = MemoryToolArguments(call.arguments)
            let query = try arguments.requiredTrimmedString("query")
            let limit = arguments.optionalClampedLimit(defaultValue: 20, maximum: 100)
            let memories = try await memoryManager.searchMemories(
                query: query,
                scope: .user,
                limit: limit
            )
            return ToolResult(
                callID: call.id,
                content: MemoryToolFormatter.encodedSearch(query: query, memories: memories)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemoryUpdateTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.updateID,
        displayName: "Update Memory",
        summary: "Update a saved memory when the user asks.",
        symbolName: "pencil",
        parameters: MemoryToolSchemas.updateMemory
    )

    private let memoryManager: MemoryManager

    init(memoryManager: MemoryManager) {
        self.memoryManager = memoryManager
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = MemoryToolArguments(call.arguments)
            let id = try arguments.requiredUUID("id")
            let text = try arguments.requiredTrimmedString("text")
            guard var memory = try await memoryManager.memory(id: id) else {
                return ToolResult(
                    callID: call.id,
                    content: "No memory exists for id \(id.uuidString).",
                    status: .error
                )
            }

            memory.text = text
            memory.updatedAt = Date()
            try await memoryManager.saveMemory(memory)
            return ToolResult(
                callID: call.id,
                content: MemoryToolFormatter.encodedUpdate(memory: memory)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

private enum MemoryToolSchemas {
    static let addMemory = objectSchema(
        properties: [
            "text": stringSchema(description: "The durable fact or preference to remember about the user.")
        ],
        required: ["text"]
    )

    static let deleteMemory = objectSchema(
        properties: [
            "id": stringSchema(description: "The UUID of the memory to delete.")
        ],
        required: ["id"]
    )

    static let listMemories = objectSchema(
        properties: [
            "limit": integerSchema(description: "Maximum number of memories to return. Defaults to 20.")
        ],
        required: []
    )

    static let searchMemories = objectSchema(
        properties: [
            "query": stringSchema(description: "Keywords to search for in saved memories."),
            "limit": integerSchema(description: "Maximum number of memories to return. Defaults to 20.")
        ],
        required: ["query"]
    )

    static let updateMemory = objectSchema(
        properties: [
            "id": stringSchema(description: "The UUID of the memory to update."),
            "text": stringSchema(description: "The replacement text for the memory.")
        ],
        required: ["id", "text"]
    )

    private static func objectSchema(
        properties: [String: JSONValue],
        required: [String]
    ) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
            "additionalProperties": .bool(false)
        ])
    }

    private static func stringSchema(description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private static func integerSchema(description: String) -> JSONValue {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(1),
            "maximum": .int(100)
        ])
    }
}

private struct MemoryToolArguments {
    private let arguments: [String: JSONValue]

    init(_ arguments: [String: JSONValue]) {
        self.arguments = arguments
    }

    func requiredTrimmedString(_ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue else {
            throw MemoryToolInputError.missingArgument(key)
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw MemoryToolInputError.emptyArgument(key)
        }

        return trimmedValue
    }

    func requiredUUID(_ key: String) throws -> UUID {
        let value = try requiredTrimmedString(key)
        guard let id = UUID(uuidString: value) else {
            throw MemoryToolInputError.invalidUUID(key)
        }

        return id
    }

    func optionalClampedLimit(defaultValue: Int, maximum: Int) -> Int {
        guard let value = arguments["limit"] else {
            return defaultValue
        }

        let limit: Int?
        switch value {
        case let .int(intValue):
            limit = intValue
        case let .double(doubleValue):
            limit = Int(doubleValue)
        case let .string(stringValue):
            limit = Int(stringValue)
        default:
            limit = nil
        }

        guard let limit else {
            return defaultValue
        }

        return min(max(1, limit), maximum)
    }
}

private enum MemoryToolInputError: LocalizedError {
    case missingArgument(String)
    case emptyArgument(String)
    case invalidUUID(String)

    var errorDescription: String? {
        switch self {
        case let .missingArgument(key):
            return "Missing required argument: \(key)."
        case let .emptyArgument(key):
            return "Argument cannot be empty: \(key)."
        case let .invalidUUID(key):
            return "Argument must be a valid UUID: \(key)."
        }
    }
}

nonisolated private enum MemoryToolFormatter {
    nonisolated private struct MemoryPayload: Encodable {
        var id: String
        var text: String
        var createdAt: String
        var updatedAt: String

        private enum CodingKeys: String, CodingKey {
            case id
            case text
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        nonisolated init(memory: MemoryRecord) {
            id = memory.id.uuidString
            text = memory.text
            createdAt = MemoryToolFormatter.string(from: memory.createdAt)
            updatedAt = MemoryToolFormatter.string(from: memory.updatedAt)
        }
    }

    nonisolated private struct MemoryListPayload: Encodable {
        var count: Int
        var memories: [MemoryPayload]
    }

    nonisolated private struct MemorySearchPayload: Encodable {
        var query: String
        var count: Int
        var memories: [MemoryPayload]
    }

    nonisolated private struct MutationPayload: Encodable {
        var status: String
        var memory: MemoryPayload?
        var id: String?
    }

    nonisolated static func encodedAdd(memory: MemoryRecord) -> String {
        encoded(MutationPayload(status: "saved", memory: MemoryPayload(memory: memory), id: nil))
    }

    nonisolated static func encodedDelete(id: UUID) -> String {
        encoded(MutationPayload(status: "deleted", memory: nil, id: id.uuidString))
    }

    nonisolated static func encodedUpdate(memory: MemoryRecord) -> String {
        encoded(MutationPayload(status: "updated", memory: MemoryPayload(memory: memory), id: nil))
    }

    nonisolated static func encodedList(memories: [MemoryRecord]) -> String {
        encoded(
            MemoryListPayload(
                count: memories.count,
                memories: memories.map(MemoryPayload.init(memory:))
            )
        )
    }

    nonisolated static func encodedSearch(query: String, memories: [MemoryRecord]) -> String {
        encoded(
            MemorySearchPayload(
                query: query,
                count: memories.count,
                memories: memories.map(MemoryPayload.init(memory:))
            )
        )
    }

    nonisolated private static func encoded<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return string
    }

    nonisolated private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
