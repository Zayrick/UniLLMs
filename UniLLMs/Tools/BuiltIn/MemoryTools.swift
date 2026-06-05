//
//  MemoryTools.swift
//  UniLLMs
//
//  Built-in tools that let a model manage the user's saved memories.
//

import Foundation

nonisolated struct MemoryToolUserFacingItem: Equatable {
    let id: String
    let title: String
    let symbolName: String
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
            title: String(localized: .toolsMemorySaveAction),
            symbolName: "plus.circle"
        ),
        MemoryToolUserFacingItem(
            id: searchID,
            title: String(localized: .toolsMemoryFindAction),
            symbolName: "magnifyingglass"
        ),
        MemoryToolUserFacingItem(
            id: listID,
            title: String(localized: .toolsMemoryViewAction),
            symbolName: "list.bullet"
        ),
        MemoryToolUserFacingItem(
            id: updateID,
            title: String(localized: .toolsMemoryUpdateAction),
            symbolName: "pencil"
        ),
        MemoryToolUserFacingItem(
            id: deleteID,
            title: String(localized: .toolsMemoryDeleteAction),
            symbolName: "trash"
        )
    ]

    static let toolIDs = userFacingItems.map(\.id)

    static func containsTool(id: String) -> Bool {
        toolIDs.contains(id)
    }
}

struct MemoryAddTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.addID,
        displayName: String(localized: .toolsMemorySaveName),
        summary: String(localized: .toolsMemorySaveSummary),
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
            let savedMemory = try await memoryManager.saveMemory(scope: .user, text: text)

            return ToolResult(
                callID: call.id,
                content: try MemoryToolFormatter.encodedAdd(memory: savedMemory)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemoryDeleteTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.deleteID,
        displayName: String(localized: .toolsMemoryDeleteName),
        summary: String(localized: .toolsMemoryDeleteSummary),
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
                    content: String(localized: .memoriesErrorMissingMemoryFormat(id.uuidString)),
                    status: .error
                )
            }

            return ToolResult(
                callID: call.id,
                content: try MemoryToolFormatter.encodedDelete(id: id)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemoryListTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.listID,
        displayName: String(localized: .toolsMemoryViewName),
        summary: String(localized: .toolsMemoryViewSummary),
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
            let limit = try arguments.optionalLimit(defaultValue: 20, maximum: 100)
            let memories = try await memoryManager.searchMemories(
                query: "",
                scope: .user,
                limit: limit
            )
            return ToolResult(
                callID: call.id,
                content: try MemoryToolFormatter.encodedList(memories: memories)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemorySearchTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.searchID,
        displayName: String(localized: .toolsMemoryFindName),
        summary: String(localized: .toolsMemoryFindSummary),
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
            let limit = try arguments.optionalLimit(defaultValue: 20, maximum: 100)
            let memories = try await memoryManager.searchMemories(
                query: query,
                scope: .user,
                limit: limit
            )
            return ToolResult(
                callID: call.id,
                content: try MemoryToolFormatter.encodedSearch(query: query, memories: memories)
            )
        } catch let error as MemoryToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct MemoryUpdateTool: Tool {
    let definition = ToolDefinition(
        name: MemoryToolCatalog.updateID,
        displayName: String(localized: .toolsMemoryUpdateName),
        summary: String(localized: .toolsMemoryUpdateSummary),
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
                    content: String(localized: .memoriesErrorMissingMemoryFormat(id.uuidString)),
                    status: .error
                )
            }

            memory.text = text
            let savedMemory = try await memoryManager.saveMemory(memory)
            return ToolResult(
                callID: call.id,
                content: try MemoryToolFormatter.encodedUpdate(memory: savedMemory)
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

    func optionalLimit(defaultValue: Int, maximum: Int) throws -> Int {
        guard let value = arguments["limit"] else {
            return defaultValue
        }

        let limit: Int
        switch value {
        case let .int(intValue):
            limit = intValue
        case let .double(doubleValue):
            guard doubleValue.rounded() == doubleValue,
                  (1...Double(maximum)).contains(doubleValue) else {
                throw MemoryToolInputError.invalidLimit("limit", maximum: maximum)
            }
            limit = Int(doubleValue)
        case let .string(stringValue):
            guard let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw MemoryToolInputError.invalidLimit("limit", maximum: maximum)
            }
            limit = intValue
        default:
            throw MemoryToolInputError.invalidLimit("limit", maximum: maximum)
        }

        guard (1...maximum).contains(limit) else {
            throw MemoryToolInputError.invalidLimit("limit", maximum: maximum)
        }

        return limit
    }
}

private enum MemoryToolInputError: LocalizedError {
    case missingArgument(String)
    case emptyArgument(String)
    case invalidUUID(String)
    case invalidLimit(String, maximum: Int)

    var errorDescription: String? {
        switch self {
        case let .missingArgument(key):
            return String(localized: .memoriesErrorMissingArgumentFormat(key))
        case let .emptyArgument(key):
            return String(localized: .memoriesErrorEmptyArgumentFormat(key))
        case let .invalidUUID(key):
            return String(localized: .memoriesErrorInvalidUuidFormat(key))
        case let .invalidLimit(key, maximum):
            return String(localized: .memoriesErrorInvalidLimitFormat(maximum, key))
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

    nonisolated static func encodedAdd(memory: MemoryRecord) throws -> String {
        try encoded(MutationPayload(status: "saved", memory: MemoryPayload(memory: memory), id: nil))
    }

    nonisolated static func encodedDelete(id: UUID) throws -> String {
        try encoded(MutationPayload(status: "deleted", memory: nil, id: id.uuidString))
    }

    nonisolated static func encodedUpdate(memory: MemoryRecord) throws -> String {
        try encoded(MutationPayload(status: "updated", memory: MemoryPayload(memory: memory), id: nil))
    }

    nonisolated static func encodedList(memories: [MemoryRecord]) throws -> String {
        try encoded(
            MemoryListPayload(
                count: memories.count,
                memories: memories.map(MemoryPayload.init(memory:))
            )
        )
    }

    nonisolated static func encodedSearch(query: String, memories: [MemoryRecord]) throws -> String {
        try encoded(
            MemorySearchPayload(
                query: query,
                count: memories.count,
                memories: memories.map(MemoryPayload.init(memory:))
            )
        )
    }

    nonisolated private static func encoded<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
