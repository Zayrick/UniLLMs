//
//  NetworkRequestTool.swift
//  UniLLMs
//
//  Built-in HTTP request tool for model-initiated network calls.
//

import Foundation

nonisolated enum NetworkToolCatalog {
    static let requestID = "http_request"

    static let toolIDs = [
        requestID
    ]

    static func containsTool(id: String) -> Bool {
        toolIDs.contains(id)
    }
}

private typealias ApprovalDetailBuilder = ToolApprovalDetailBuilder

struct NetworkToolApprovalRequestProvider: ToolApprovalRequestProviding {
    let toolIDs = Set(NetworkToolCatalog.toolIDs)

    func approvalRequest(
        for call: ToolCall,
        definition: ToolDefinition
    ) async -> ToolApprovalRequest? {
        guard NetworkToolCatalog.containsTool(id: call.toolID) else {
            return nil
        }

        return ToolApprovalRequest(
            toolID: call.toolID,
            toolName: definition.presentationName,
            confirmationTitle: String(localized: "tools.approval.allow_request"),
            isDestructive: false,
            details: details(for: call)
        )
    }

    func details(for call: ToolCall) -> [ToolApprovalDetail] {
        let method = NetworkRequestToolArguments.methodText(call.arguments["method"]) ?? "GET"
        return ApprovalDetailBuilder.compact([
            ApprovalDetailBuilder.detail("tools.approval.detail.method", value: method),
            ApprovalDetailBuilder.detail(
                "tools.approval.detail.url",
                value: NetworkRequestToolArguments.approvalURLText(from: call.arguments)
            ),
            ApprovalDetailBuilder.detail(
                "tools.approval.detail.headers",
                value: NetworkRequestToolArguments.approvalHeadersText(call.arguments["headers"])
            ),
            ApprovalDetailBuilder.detail(
                "tools.approval.detail.body",
                value: NetworkRequestToolArguments.approvalBodyText(call.arguments["body"])
            ),
            ApprovalDetailBuilder.detail(
                "tools.approval.detail.timeout",
                value: NetworkRequestToolArguments.timeoutText(call.arguments["timeout_seconds"])
            )
        ])
    }
}

struct NetworkRequestTool: Tool {
    let definition = ToolDefinition(
        name: NetworkToolCatalog.requestID,
        displayName: String(localized: "tools.network_request.name"),
        summary: String(localized: "tools.network_request.summary"),
        symbolName: "network",
        parameters: NetworkRequestToolSchemas.request
    )

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = NetworkRequestToolArguments(call.arguments)
            let request = try arguments.request()
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolResult(
                    callID: call.id,
                    content: NSLocalizedString("tools.network.error.non_http_response", comment: ""),
                    status: .error
                )
            }

            let content = try NetworkRequestToolFormatter.encodedResponse(
                data: data,
                response: httpResponse
            )
            return ToolResult(
                callID: call.id,
                content: content,
                status: (200..<400).contains(httpResponse.statusCode) ? .success : .error
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NetworkRequestToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch {
            return ToolResult(
                callID: call.id,
                content: String(
                    format: NSLocalizedString("tools.network.error.request_failed_format", comment: ""),
                    locale: Locale.current,
                    error.localizedDescription
                ),
                status: .error
            )
        }
    }
}

private enum NetworkRequestToolSchemas {
    static let request = objectSchema(
        properties: [
            "method": .object([
                "type": .string("string"),
                "description": .string("HTTP method. Defaults to GET."),
                "enum": .array(NetworkRequestToolArguments.allowedMethods.map(JSONValue.string))
            ]),
            "url": stringSchema(description: "Absolute http or https URL to request."),
            "headers": .object([
                "type": .string("object"),
                "description": .string("Optional HTTP request headers."),
                "additionalProperties": .object([
                    "type": .string("string")
                ])
            ]),
            "query": .object([
                "type": .string("object"),
                "description": .string("Optional query parameters appended to the URL."),
                "additionalProperties": .object([:])
            ]),
            "body": .object([
                "description": .string("Optional request body. Strings are sent as UTF-8 text; JSON values are encoded as JSON.")
            ]),
            "timeout_seconds": .object([
                "type": .string("number"),
                "description": .string("Request timeout in seconds. Defaults to 30, maximum 120."),
                "minimum": .int(1),
                "maximum": .int(NetworkRequestToolArguments.maximumTimeoutSeconds)
            ])
        ],
        required: ["url"]
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
}

private struct NetworkRequestToolArguments {
    nonisolated static let allowedMethods = [
        "GET",
        "POST",
        "PUT",
        "PATCH",
        "DELETE",
        "HEAD",
        "OPTIONS"
    ]
    nonisolated static let defaultTimeoutSeconds = 30.0
    nonisolated static let maximumTimeoutSeconds = 120
    nonisolated static let maximumBodyByteCount = 128 * 1024

    private let arguments: [String: JSONValue]

    init(_ arguments: [String: JSONValue]) {
        self.arguments = arguments
    }

    func request() throws -> URLRequest {
        let url = try resolvedURL()
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: try timeoutSeconds()
        )
        request.httpMethod = try method()

        let headers = try headers()
        headers.forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }

        if let body = try bodyData() {
            guard body.data.count <= Self.maximumBodyByteCount else {
                throw NetworkRequestToolInputError.bodyTooLarge(Self.maximumBodyByteCount)
            }
            request.httpBody = body.data
            if body.isJSON,
               !headers.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        return request
    }

    private func method() throws -> String {
        guard let value = arguments["method"] else {
            return "GET"
        }
        guard let method = Self.methodText(value) else {
            throw NetworkRequestToolInputError.invalidMethod
        }
        guard Self.allowedMethods.contains(method) else {
            throw NetworkRequestToolInputError.invalidMethod
        }

        return method
    }

    private func resolvedURL() throws -> URL {
        let rawURL = try requiredTrimmedString("url")
        guard var components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else {
            throw NetworkRequestToolInputError.invalidURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw NetworkRequestToolInputError.unsupportedScheme(scheme)
        }

        let existingItems = components.queryItems ?? []
        components.queryItems = existingItems + (try queryItems())
        guard let url = components.url else {
            throw NetworkRequestToolInputError.invalidURL
        }

        return url
    }

    private func headers() throws -> [String: String] {
        guard let value = arguments["headers"] else {
            return [:]
        }
        guard let object = value.objectValue else {
            throw NetworkRequestToolInputError.invalidObject("headers")
        }

        var headers: [String: String] = [:]
        for (rawName, rawValue) in object {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isValidHeaderName(name),
                  let value = Self.headerValue(rawValue),
                  Self.isValidHeaderValue(value) else {
                throw NetworkRequestToolInputError.invalidHeader(rawName)
            }

            headers[name] = value
        }

        return headers
    }

    private func queryItems() throws -> [URLQueryItem] {
        guard let value = arguments["query"] else {
            return []
        }
        guard let object = value.objectValue else {
            throw NetworkRequestToolInputError.invalidObject("query")
        }

        return object.keys.sorted().flatMap { key in
            Self.queryItems(name: key, value: object[key] ?? .null)
        }
    }

    private func bodyData() throws -> (data: Data, isJSON: Bool)? {
        guard let body = arguments["body"] else {
            return nil
        }

        switch body {
        case let .string(value):
            guard let data = value.data(using: .utf8) else {
                throw NetworkRequestToolInputError.invalidBody
            }
            return (data, false)
        default:
            return (try JSONEncoder().encode(body), true)
        }
    }

    private func timeoutSeconds() throws -> TimeInterval {
        guard let value = arguments["timeout_seconds"] else {
            return Self.defaultTimeoutSeconds
        }

        let timeout: Double
        switch value {
        case let .int(value):
            timeout = Double(value)
        case let .double(value):
            timeout = value
        case let .string(value):
            guard let parsedValue = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw NetworkRequestToolInputError.invalidTimeout
            }
            timeout = parsedValue
        default:
            throw NetworkRequestToolInputError.invalidTimeout
        }

        guard timeout >= 1,
              timeout <= Double(Self.maximumTimeoutSeconds) else {
            throw NetworkRequestToolInputError.invalidTimeout
        }

        return timeout
    }

    private func requiredTrimmedString(_ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue else {
            throw NetworkRequestToolInputError.missingArgument(key)
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw NetworkRequestToolInputError.emptyArgument(key)
        }

        return trimmedValue
    }

    nonisolated static func methodText(_ value: JSONValue?) -> String? {
        guard let value = value?.stringValue else {
            return nil
        }

        let method = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return method.isEmpty ? nil : method
    }

    nonisolated static func approvalURLText(from arguments: [String: JSONValue]) -> String? {
        guard let rawURL = ApprovalDetailBuilder.stringValue(arguments["url"]) else {
            return nil
        }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            return nil
        }

        guard var components = URLComponents(string: trimmedURL),
              let query = arguments["query"]?.objectValue else {
            return trimmedURL
        }

        components.queryItems = (components.queryItems ?? []) + query.keys.sorted().flatMap { key in
            queryItems(name: key, value: query[key] ?? .null)
        }

        return components.url?.absoluteString ?? trimmedURL
    }

    nonisolated static func approvalHeadersText(_ value: JSONValue?) -> String? {
        guard let headers = value?.objectValue,
              !headers.isEmpty else {
            return nil
        }

        let redactedHeaders: [String: JSONValue] = Dictionary(uniqueKeysWithValues: headers.keys.sorted().map {
            ($0, JSONValue.string(displayHeaderValue(name: $0, value: headers[$0] ?? .null)))
        })
        return JSONValue.object(redactedHeaders).serializedJSONString
    }

    nonisolated static func approvalBodyText(_ value: JSONValue?) -> String? {
        guard let value else {
            return nil
        }

        switch value {
        case let .string(text):
            return text
        default:
            return value.serializedJSONString
        }
    }

    nonisolated static func timeoutText(_ value: JSONValue?) -> String? {
        guard let value else {
            return nil
        }

        switch value {
        case let .int(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .string(value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return nil
        }
    }

    private nonisolated static func queryItems(name: String, value: JSONValue) -> [URLQueryItem] {
        switch value {
        case let .array(values):
            return values.map {
                URLQueryItem(name: name, value: queryValue($0))
            }
        case .null:
            return [URLQueryItem(name: name, value: nil)]
        default:
            return [URLQueryItem(name: name, value: queryValue(value))]
        }
    }

    private nonisolated static func queryValue(_ value: JSONValue) -> String? {
        switch value {
        case let .string(value):
            return value
        case let .int(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return nil
        case .object, .array:
            return value.serializedJSONString
        }
    }

    private nonisolated static func headerValue(_ value: JSONValue) -> String? {
        switch value {
        case let .string(value):
            return value
        case let .int(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    private nonisolated static func isValidHeaderName(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        let separators = CharacterSet(charactersIn: "()<>@,;:\\\"/[]?={} \t")
        return value.unicodeScalars.allSatisfy {
            $0.value > 31 && $0.value != 127 && !separators.contains($0)
        }
    }

    private nonisolated static func isValidHeaderValue(_ value: String) -> Bool {
        !value.contains("\r") && !value.contains("\n")
    }

    private nonisolated static func displayHeaderValue(name: String, value: JSONValue) -> String {
        if isSensitiveHeaderName(name) {
            return "[redacted]"
        }

        return headerValue(value) ?? value.serializedJSONString ?? ""
    }

    private nonisolated static func isSensitiveHeaderName(_ name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedName == "authorization"
            || normalizedName == "proxy-authorization"
            || normalizedName == "x-api-key"
            || normalizedName == "api-key"
    }
}

private enum NetworkRequestToolInputError: LocalizedError {
    case missingArgument(String)
    case emptyArgument(String)
    case invalidMethod
    case invalidURL
    case unsupportedScheme(String)
    case invalidObject(String)
    case invalidHeader(String)
    case invalidBody
    case invalidTimeout
    case bodyTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case let .missingArgument(key):
            return Self.localized("tools.network.error.missing_argument_format", key)
        case let .emptyArgument(key):
            return Self.localized("tools.network.error.empty_argument_format", key)
        case .invalidMethod:
            return NSLocalizedString("tools.network.error.invalid_method", comment: "")
        case .invalidURL:
            return NSLocalizedString("tools.network.error.invalid_url", comment: "")
        case let .unsupportedScheme(scheme):
            return Self.localized("tools.network.error.unsupported_scheme_format", scheme)
        case let .invalidObject(key):
            return Self.localized("tools.network.error.invalid_object_format", key)
        case let .invalidHeader(header):
            return Self.localized("tools.network.error.invalid_header_format", header)
        case .invalidBody:
            return NSLocalizedString("tools.network.error.invalid_body", comment: "")
        case .invalidTimeout:
            return NSLocalizedString("tools.network.error.invalid_timeout", comment: "")
        case let .bodyTooLarge(maximumByteCount):
            return Self.localized("tools.network.error.body_too_large_format", maximumByteCount)
        }
    }

    private static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: NSLocalizedString(key, comment: ""),
            locale: Locale.current,
            arguments: arguments
        )
    }
}

nonisolated private enum NetworkRequestToolFormatter {
    nonisolated private struct ResponsePayload: Encodable {
        var statusCode: Int
        var reasonPhrase: String
        var url: String
        var headers: [String: String]
        var body: String
        var bodyEncoding: String
        var bodyByteCount: Int
        var truncated: Bool

        private enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case reasonPhrase = "reason_phrase"
            case url
            case headers
            case body
            case bodyEncoding = "body_encoding"
            case bodyByteCount = "body_byte_count"
            case truncated
        }
    }

    nonisolated private static let maximumResponseBodyByteCount = 256 * 1024

    nonisolated static func encodedResponse(data: Data, response: HTTPURLResponse) throws -> String {
        let body = responseBody(data: data, response: response)
        let payload = ResponsePayload(
            statusCode: response.statusCode,
            reasonPhrase: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
            url: response.url?.absoluteString ?? "",
            headers: responseHeaders(response),
            body: body.text,
            bodyEncoding: body.encoding,
            bodyByteCount: data.count,
            truncated: body.truncated
        )
        let encodedData = try JSONEncoder().encode(payload)
        return String(decoding: encodedData, as: UTF8.self)
    }

    nonisolated private static func responseBody(
        data: Data,
        response: HTTPURLResponse
    ) -> (text: String, encoding: String, truncated: Bool) {
        let truncated = data.count > maximumResponseBodyByteCount
        let bodyData = truncated ? data.prefix(maximumResponseBodyByteCount) : data[...]
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""

        if isTextualContentType(contentType) {
            return (String(decoding: bodyData, as: UTF8.self), "utf-8", truncated)
        }

        if let text = String(data: Data(bodyData), encoding: .utf8) {
            return (text, "utf-8", truncated)
        }

        return (Data(bodyData).base64EncodedString(), "base64", truncated)
    }

    nonisolated private static func responseHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return headers
    }

    nonisolated private static func isTextualContentType(_ value: String) -> Bool {
        let contentType = value.lowercased()
        return contentType.hasPrefix("text/")
            || contentType.contains("json")
            || contentType.contains("xml")
            || contentType.contains("javascript")
            || contentType.contains("x-www-form-urlencoded")
    }
}
