//
//  MCPHTTPClient.swift
//  UniLLMs
//
//  Implements a minimal Streamable HTTP MCP client for tool discovery and tool calls.
//  Created by Zayrick on 2026/5/15.
//

import Foundation

final class MCPHTTPClient: MCPClient {
    nonisolated private enum Constants {
        static let requestedProtocolVersion = "2025-11-25"
        static let clientName = "UniLLMs"
        static let clientVersion = "1.0"
        static let modelToolNameLimit = 64
    }

    nonisolated private struct JSONRPCMessage: Encodable {
        var jsonrpc = "2.0"
        var id: Int?
        var method: String
        var params: JSONValue?
    }

    nonisolated private struct JSONRPCResponse: Decodable {
        var id: JSONValue?
        var result: JSONValue?
        var error: JSONRPCError?
    }

    nonisolated private struct JSONRPCError: Decodable {
        var code: Int
        var message: String
        var data: JSONValue?
    }

    private let server: MCPServerRecord
    private let session: URLSession
    private var nextRequestID = 1
    private var sessionID: String?
    private var negotiatedProtocolVersion = Constants.requestedProtocolVersion

    init(server: MCPServerRecord) {
        self.server = server

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = server.configuration.timeout
        configuration.timeoutIntervalForResource = server.configuration.timeout
        session = URLSession(configuration: configuration)
    }

    func connect() async throws {
        let result = try await sendRequest(
            method: "initialize",
            params: .object([
                "protocolVersion": .string(Constants.requestedProtocolVersion),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string(Constants.clientName),
                    "version": .string(Constants.clientVersion)
                ])
            ])
        )

        if let protocolVersion = result.objectValue?["protocolVersion"]?.stringValue,
           !protocolVersion.isEmpty {
            negotiatedProtocolVersion = protocolVersion
        }

        try await sendNotification(method: "notifications/initialized", params: nil)
    }

    func loadTools() async throws -> [MCPToolDescriptor] {
        var descriptors: [MCPToolDescriptor] = []
        var cursor: String?
        var usedModelNames = Set<String>()

        repeat {
            let params: JSONValue?
            if let cursor {
                params = .object(["cursor": .string(cursor)])
            } else {
                params = nil
            }
            let result = try await sendRequest(method: "tools/list", params: params)
            let tools = result.objectValue?["tools"]?.arrayValue ?? []
            for toolValue in tools {
                guard let descriptor = toolDescriptor(
                    from: toolValue,
                    usedModelNames: &usedModelNames
                ) else {
                    continue
                }
                descriptors.append(descriptor)
            }
            cursor = result.objectValue?["nextCursor"]?.stringValue
        } while cursor != nil

        return descriptors
    }

    func callTool(originalName: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        let result = try await sendRequest(
            method: "tools/call",
            params: .object([
                "name": .string(originalName),
                "arguments": .object(arguments)
            ])
        )

        return Self.toolResult(from: result)
    }

    private func toolDescriptor(
        from value: JSONValue,
        usedModelNames: inout Set<String>
    ) -> MCPToolDescriptor? {
        guard let object = value.objectValue,
              let originalName = object["name"]?.stringValue,
              !originalName.isEmpty else {
            return nil
        }

        let modelName = Self.modelToolName(
            serverID: server.id,
            toolName: originalName,
            usedNames: usedModelNames
        )
        usedModelNames.insert(modelName)

        let title = object["title"]?.stringValue
        let description = object["description"]?.stringValue
        let summary = [
            description ?? title ?? originalName,
            "Server: \(server.displayName)"
        ].joined(separator: "\n")

        let inputSchema = object["inputSchema"] ?? JSONValue.emptyObjectSchema
        let definition = ToolDefinition(
            name: modelName,
            displayName: title ?? originalName,
            summary: summary,
            parameters: Self.normalizedToolSchema(inputSchema)
        )
        return MCPToolDescriptor(originalName: originalName, definition: definition)
    }

    private func sendRequest(
        method: String,
        params: JSONValue?
    ) async throws -> JSONValue {
        let requestID = nextRequestID
        nextRequestID += 1

        let message = JSONRPCMessage(id: requestID, method: method, params: params)
        let response = try await send(message: message, expectsResponse: true)
        if let error = response.error {
            throw MCPHTTPClientError.rpcError(error.message, code: error.code)
        }

        return response.result ?? .object([:])
    }

    private func sendNotification(method: String, params: JSONValue?) async throws {
        let message = JSONRPCMessage(id: nil, method: method, params: params)
        _ = try await send(message: message, expectsResponse: false)
    }

    private func send(
        message: JSONRPCMessage,
        expectsResponse: Bool
    ) async throws -> JSONRPCResponse {
        var request = URLRequest(url: try endpointURL())
        request.httpMethod = "POST"
        request.timeoutInterval = server.configuration.timeout
        for (key, value) in server.configuration.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(negotiatedProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "MCP-Session-Id")
        }
        request.httpBody = try JSONEncoder().encode(message)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPHTTPClientError.invalidResponse(server.displayName)
        }

        if let receivedSessionID = Self.headerValue("MCP-Session-Id", in: httpResponse) {
            sessionID = receivedSessionID
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MCPHTTPClientError.httpStatus(
                server.displayName,
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        guard expectsResponse else {
            return JSONRPCResponse(id: nil, result: nil, error: nil)
        }

        return try Self.decodeResponse(
            data: data,
            contentType: Self.headerValue("Content-Type", in: httpResponse),
            serverName: server.displayName
        )
    }

    private func endpointURL() throws -> URL {
        let endpoint = server.configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: endpoint),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.query == nil,
              components.fragment == nil,
              let url = components.url else {
            throw MCPHTTPClientError.invalidEndpoint(endpoint)
        }

        return url
    }

    nonisolated private static func decodeResponse(
        data: Data,
        contentType: String?,
        serverName: String
    ) throws -> JSONRPCResponse {
        if contentType?.localizedCaseInsensitiveContains("text/event-stream") == true {
            guard let text = String(data: data, encoding: .utf8) else {
                throw MCPHTTPClientError.invalidResponse(serverName)
            }

            for line in text.components(separatedBy: .newlines) {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLine.hasPrefix("data:") else {
                    continue
                }

                let payload = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard !payload.isEmpty,
                      let payloadData = payload.data(using: .utf8),
                      let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: payloadData) else {
                    continue
                }

                if response.result != nil || response.error != nil {
                    return response
                }
            }

            throw MCPHTTPClientError.invalidResponse(serverName)
        }

        do {
            return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        } catch {
            throw MCPHTTPClientError.invalidResponse(serverName)
        }
    }

    nonisolated private static func normalizedToolSchema(_ schema: JSONValue) -> JSONValue {
        guard var object = schema.objectValue else {
            return JSONValue.emptyObjectSchema
        }

        object["type"] = object["type"] ?? .string("object")
        object["properties"] = object["properties"] ?? .object([:])
        object["required"] = object["required"] ?? .array([])
        return .object(object)
    }

    nonisolated private static func modelToolName(
        serverID: UUID,
        toolName: String,
        usedNames: Set<String>
    ) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let sanitizedCharacters = toolName.map { character in
            String(character).unicodeScalars.allSatisfy { allowed.contains($0) }
                ? character
                : "_"
        }
        let sanitizedName = String(sanitizedCharacters).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let fallbackName = sanitizedName.isEmpty ? "tool" : sanitizedName
        let prefix = "\(MCPServerManager.mcpToolNamePrefix)\(serverID.uuidString.prefix(8))_"
        let availableCount = max(1, Constants.modelToolNameLimit - prefix.count)
        let baseName = prefix + String(fallbackName.prefix(availableCount))
        guard usedNames.contains(baseName) else {
            return baseName
        }

        var suffix = 2
        while true {
            let suffixText = "_\(suffix)"
            let trimmedBase = String(baseName.prefix(max(1, Constants.modelToolNameLimit - suffixText.count)))
            let candidate = trimmedBase + suffixText
            if !usedNames.contains(candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    nonisolated static func toolResult(from result: JSONValue) -> MCPToolResult {
        let object = result.objectValue ?? [:]
        let isError = object["isError"] == .bool(true)
        var lines: [String] = []

        if let content = object["content"]?.arrayValue {
            lines.append(
                contentsOf: content.compactMap(Self.serializedContentBlock)
            )
        }

        if let structuredContent = object["structuredContent"],
           let structuredText = structuredContent.serializedJSONString {
            lines.append("Structured content: \(structuredText)")
        }

        let text = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let fallback = isError
            ? "Tool execution failed with no output."
            : "Tool executed successfully with no output."
        return MCPToolResult(
            content: text.isEmpty ? fallback : text,
            isError: isError
        )
    }

    nonisolated private static func serializedContentBlock(_ value: JSONValue) -> String? {
        guard let object = value.objectValue,
              let type = object["type"]?.stringValue else {
            return value.serializedJSONString
        }

        switch type {
        case "text":
            return object["text"]?.stringValue
        case "image":
            return "[Image: \(object["mimeType"]?.stringValue ?? "unknown")]"
        case "audio":
            return "[Audio: \(object["mimeType"]?.stringValue ?? "unknown")]"
        case "resource_link":
            return "[Resource: \(object["uri"]?.stringValue ?? "unknown")]"
        case "resource":
            if let resource = object["resource"]?.objectValue,
               let text = resource["text"]?.stringValue {
                return text
            }
            return value.serializedJSONString
        default:
            return value.serializedJSONString
        }
    }

    nonisolated private static func headerValue(_ name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String,
                  key.caseInsensitiveCompare(name) == .orderedSame else {
                continue
            }

            return value as? String
        }

        return nil
    }
}

enum MCPHTTPClientError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case invalidResponse(String)
    case httpStatus(String, statusCode: Int, body: String?)
    case rpcError(String, code: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(endpoint):
            return "Invalid MCP endpoint: \(endpoint)"
        case let .invalidResponse(serverName):
            return "\(serverName) returned an invalid MCP response."
        case let .httpStatus(serverName, statusCode, body):
            if let body, !body.isEmpty {
                return "\(serverName) returned HTTP \(statusCode): \(body)"
            }
            return "\(serverName) returned HTTP \(statusCode)."
        case let .rpcError(message, code):
            return "MCP JSON-RPC \(code): \(message)"
        }
    }
}
