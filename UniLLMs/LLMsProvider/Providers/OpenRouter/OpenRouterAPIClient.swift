//
//  OpenRouterAPIClient.swift
//  UniLLMs
//
//  Created by ZayrickRouter HTTP and SSE API details, including requests, response parsing, and error conversion.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated enum OpenRouterMessageContent: Codable, Equatable {
    case text(String)
    case parts([OpenRouterContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
            return
        }
        if let parts = try? container.decode([OpenRouterContentPart].self) {
            self = .parts(parts)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported message content payload."
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(string):
            try container.encode(string)
        case let .parts(parts):
            try container.encode(parts)
        }
    }
}

nonisolated enum OpenRouterContentPart: Codable, Equatable {
    case text(String)
    case imageURL(url: String)
    case file(filename: String, fileData: String)

    nonisolated private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case file
    }

    nonisolated private struct ImageURLPayload: Codable, Equatable {
        var url: String
    }

    nonisolated private struct FilePayload: Codable, Equatable {
        var filename: String
        var fileData: String

        nonisolated private enum CodingKeys: String, CodingKey {
            case filename
            case fileData = "file_data"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            let payload = try container.decode(ImageURLPayload.self, forKey: .imageURL)
            self = .imageURL(url: payload.url)
        case "file":
            let payload = try container.decode(FilePayload.self, forKey: .file)
            self = .file(filename: payload.filename, fileData: payload.fileData)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported content part type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(string):
            try container.encode("text", forKey: .type)
            try container.encode(string, forKey: .text)
        case let .imageURL(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: url), forKey: .imageURL)
        case let .file(filename, fileData):
            try container.encode("file", forKey: .type)
            try container.encode(
                FilePayload(filename: filename, fileData: fileData),
                forKey: .file
            )
        }
    }
}

nonisolated struct OpenRouterChatMessage: Codable, Equatable {
    nonisolated enum Role: String, Codable {
        case user
        case assistant
        case system
        case tool
    }

    nonisolated struct ToolCall: Codable, Equatable {
        nonisolated struct Function: Codable, Equatable {
            var name: String
            var arguments: String
        }

        var id: String
        var type: String
        var function: Function
    }

    var role: Role
    var content: OpenRouterMessageContent?
    var toolCalls: [ToolCall]?
    var toolCallID: String?

    nonisolated private enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let content {
            try container.encode(content, forKey: .content)
        } else if role == .assistant,
                  toolCalls?.isEmpty == false {
            try container.encodeNil(forKey: .content)
        }
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }
}

nonisolated struct OpenRouterChatTool: Encodable, Equatable {
    nonisolated struct Function: Encodable, Equatable {
        var name: String
        var description: String
        var parameters: JSONValue
    }

    var type = "function"
    var function: Function

    init(definition: ToolDefinition) {
        function = Function(
            name: definition.name,
            description: definition.summary,
            parameters: definition.parameters
        )
    }
}

nonisolated struct OpenRouterToolCallDelta: Equatable {
    var index: Int
    var id: String?
    var name: String?
    var argumentsFragment: String
}

nonisolated struct OpenRouterChatStreamDelta: Equatable {
    var content: String = ""
    var reasoning: String = ""
    var toolCallDeltas: [OpenRouterToolCallDelta] = []
    var toolCalls: [ChatToolCall] = []

    var isEmpty: Bool {
        content.isEmpty && reasoning.isEmpty && toolCallDeltas.isEmpty && toolCalls.isEmpty
    }
}

nonisolated struct OpenRouterAPIClient {
    nonisolated enum APIError: LocalizedError, Equatable {
        case invalidAPIBase(String)
        case invalidResponse(String)
        case serverStatus(String, Int, String?)
        case streamError(String)

        var errorDescription: String? {
            switch self {
            case let .invalidAPIBase(apiBase):
                return "Invalid API Base: \(apiBase)"
            case let .invalidResponse(serviceName):
                return "\(serviceName) returned an invalid response."
            case let .serverStatus(serviceName, statusCode, message):
                if let message, !message.isEmpty {
                    return "\(serviceName) returned HTTP \(statusCode): \(message)"
                }
                return "\(serviceName) returned HTTP \(statusCode)."
            case let .streamError(message):
                return message
            }
        }
    }

    nonisolated private struct ChatCompletionsRequest: Encodable {
        var model: String
        var messages: [OpenRouterChatMessage]
        var stream: Bool
        var tools: [OpenRouterChatTool]?
    }

    nonisolated private struct ChatCompletionChunk: Decodable {
        var choices: [Choice]?
        var error: ResponseError?

        nonisolated struct Choice: Decodable {
            var delta: Delta?
            var finishReason: String?

            nonisolated private enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        nonisolated struct Delta: Decodable {
            var content: String?
            var reasoning: String?
            var reasoningContent: String?
            var reasoningDetails: [ReasoningDetail]?
            var toolCalls: [ToolCall]?

            nonisolated private enum CodingKeys: String, CodingKey {
                case content
                case reasoning
                case reasoningContent = "reasoning_content"
                case reasoningDetails = "reasoning_details"
                case toolCalls = "tool_calls"
            }
        }

        nonisolated struct ReasoningDetail: Decodable {
            var type: String?
            var text: String?
            var summary: String?
        }

        nonisolated struct ToolCall: Decodable {
            var index: Int?
            var id: String?
            var type: String?
            var function: Function?

            nonisolated struct Function: Decodable {
                var name: String?
                var arguments: String?
            }
        }

        nonisolated struct ResponseError: Decodable {
            var message: String?
        }
    }

    nonisolated private struct ModelsResponse: Decodable {
        var data: [Model]
    }

    nonisolated private struct Model: Decodable {
        var id: String
        var name: String?
        var contextLength: Int?

        nonisolated private enum CodingKeys: String, CodingKey {
            case id
            case name
            case contextLength = "context_length"
        }
    }

    nonisolated private static let defaultServiceName = "OpenRouter"
    nonisolated private static let defaultAPIBaseValue = "https://openrouter.ai/api/v1"

    var session: URLSession = .shared
    var serviceName: String = Self.defaultServiceName
    var defaultAPIBase: String = Self.defaultAPIBaseValue

    func streamChatCompletion(
        apiBase: String,
        apiKey: String,
        model: String,
        messages: [OpenRouterChatMessage],
        tools: [OpenRouterChatTool] = []
    ) -> AsyncThrowingStream<OpenRouterChatStreamDelta, Error> {
        streamChatCompletion(
            apiBase: apiBase,
            authorizationHeader: Self.bearerAuthorizationHeader(apiKey: apiKey),
            model: model,
            messages: messages,
            tools: tools
        )
    }

    private func streamChatCompletion(
        apiBase: String,
        authorizationHeader: String,
        model: String,
        messages: [OpenRouterChatMessage],
        tools: [OpenRouterChatTool]
    ) -> AsyncThrowingStream<OpenRouterChatStreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatCompletionsRequest(
                        apiBase: apiBase,
                        authorizationHeader: authorizationHeader,
                        model: model,
                        messages: messages,
                        tools: tools
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse(serviceName)
                    }

                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await responseBodyString(from: bytes)
                        throw APIError.serverStatus(serviceName, httpResponse.statusCode, body)
                    }

                    var toolCallAccumulator = ToolCallAccumulator()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if Self.isDoneServerSentEventLine(line) {
                            break
                        }

                        guard let delta = try Self.streamDelta(
                            fromServerSentEventLine: line,
                            serviceName: serviceName
                        ) else {
                            continue
                        }

                        toolCallAccumulator.append(delta.toolCallDeltas)
                        let responseDelta = OpenRouterChatStreamDelta(
                            content: delta.content,
                            reasoning: delta.reasoning
                        )
                        if !responseDelta.isEmpty {
                            continuation.yield(responseDelta)
                        }
                    }

                    let toolCalls = toolCallAccumulator.completedToolCalls()
                    if !toolCalls.isEmpty {
                        continuation.yield(OpenRouterChatStreamDelta(toolCalls: toolCalls))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func fetchModels(apiBase: String, apiKey: String) async throws -> [LLMsProviderModel] {
        var request = URLRequest(url: try modelsURL(apiBase: apiBase))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(serviceName)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw APIError.serverStatus(serviceName, httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data
            .map {
                LLMsProviderModel(
                    id: $0.id,
                    name: $0.name,
                    contextLength: $0.contextLength
                )
            }
    }

    private func modelsURL(apiBase: String) throws -> URL {
        try normalizedAPIBaseURL(apiBase: apiBase)
            .appendingPathComponent("models")
            .appendingPathComponent("user")
    }

    private func chatCompletionsRequest(
        apiBase: String,
        authorizationHeader: String,
        model: String,
        messages: [OpenRouterChatMessage],
        tools: [OpenRouterChatTool]
    ) throws -> URLRequest {
        var request = URLRequest(url: try chatCompletionsURL(apiBase: apiBase))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let trimmedAuthorizationHeader = authorizationHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAuthorizationHeader.isEmpty {
            request.setValue(trimmedAuthorizationHeader, forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(
            ChatCompletionsRequest(
                model: model,
                messages: messages,
                stream: true,
                tools: tools.isEmpty ? nil : tools
            )
        )
        return request
    }

    private func chatCompletionsURL(apiBase: String) throws -> URL {
        try normalizedAPIBaseURL(apiBase: apiBase)
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    private func responseBodyString(from bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            if !body.isEmpty {
                body.append("\n")
            }
            body.append(line)
            if body.count > 2_048 {
                break
            }
        }
        return body
    }

    private func normalizedAPIBaseURL(apiBase: String) throws -> URL {
        let trimmedAPIBase = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseString = trimmedAPIBase.isEmpty
            ? defaultAPIBase
            : trimmedAPIBase

        guard var components = URLComponents(string: baseString),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.query == nil,
              components.fragment == nil else {
            throw APIError.invalidAPIBase(baseString)
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedPath.isEmpty ? "" : "/\(trimmedPath)"
        guard let baseURL = components.url else {
            throw APIError.invalidAPIBase(baseString)
        }

        return baseURL
    }

    nonisolated static func streamDelta(
        fromServerSentEventLine line: String,
        serviceName: String = defaultServiceName
    ) throws -> OpenRouterChatStreamDelta? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty,
              !trimmedLine.hasPrefix(":") else {
            return nil
        }

        guard trimmedLine.hasPrefix("data:") else {
            return nil
        }

        let dataPrefixEndIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 5)
        let payload = trimmedLine[dataPrefixEndIndex...]
            .trimmingCharacters(in: .whitespaces)

        guard payload != "[DONE]" else {
            return nil
        }

        guard let data = payload.data(using: .utf8) else {
            throw APIError.invalidResponse(serviceName)
        }

        let chunk: ChatCompletionChunk
        do {
            chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
        } catch {
            throw APIError.invalidResponse(serviceName)
        }

        if let errorMessage = chunk.error?.message,
           !errorMessage.isEmpty {
            throw APIError.streamError(errorMessage)
        }

        let deltas = chunk.choices?
            .compactMap(\.delta)
            .map(Self.streamDelta)
            ?? []

        let content = deltas.map(\.content).joined()
        let reasoning = deltas.map(\.reasoning).joined()
        let toolCallDeltas = deltas.flatMap(\.toolCallDeltas)
        let delta = OpenRouterChatStreamDelta(
            content: content,
            reasoning: reasoning,
            toolCallDeltas: toolCallDeltas
        )
        return delta.isEmpty ? nil : delta
    }

    nonisolated private static func isDoneServerSentEventLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]"
    }

    nonisolated private static func bearerAuthorizationHeader(apiKey: String) -> String {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAPIKey.isEmpty ? "" : "Bearer \(trimmedAPIKey)"
    }

    nonisolated private static func streamDelta(
        from delta: ChatCompletionChunk.Delta
    ) -> OpenRouterChatStreamDelta {
        let reasoningFromDetails = delta.reasoningDetails?
            .compactMap { detail in
                detail.text ?? detail.summary
            }
            .joined()
            ?? ""
        let reasoningFromStringFields = [
            delta.reasoning,
            delta.reasoningContent
        ]
            .compactMap { $0 }
            .joined()

        return OpenRouterChatStreamDelta(
            content: delta.content ?? "",
            reasoning: reasoningFromDetails.isEmpty ? reasoningFromStringFields : reasoningFromDetails,
            toolCallDeltas: toolCallDeltas(from: delta)
        )
    }

    nonisolated private static func toolCallDeltas(
        from delta: ChatCompletionChunk.Delta
    ) -> [OpenRouterToolCallDelta] {
        delta.toolCalls?.compactMap { toolCall in
            guard let index = toolCall.index else {
                return nil
            }

            return OpenRouterToolCallDelta(
                index: index,
                id: toolCall.id,
                name: toolCall.function?.name,
                argumentsFragment: toolCall.function?.arguments ?? ""
            )
        } ?? []
    }
}

nonisolated private struct ToolCallAccumulator {
    nonisolated private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var partials: [Int: PartialToolCall] = [:]

    mutating func append(_ deltas: [OpenRouterToolCallDelta]) {
        for delta in deltas {
            var partial = partials[delta.index] ?? PartialToolCall()
            if let id = delta.id, !id.isEmpty {
                partial.id = id
            }
            if let name = delta.name, !name.isEmpty {
                partial.name = name
            }
            partial.arguments += delta.argumentsFragment
            partials[delta.index] = partial
        }
    }

    func completedToolCalls() -> [ChatToolCall] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index],
                  let name = partial.name else {
                return nil
            }

            return ChatToolCall(
                id: partial.id ?? "tool_call_\(index)",
                toolID: name,
                arguments: partial.arguments
            )
        }
    }
}
