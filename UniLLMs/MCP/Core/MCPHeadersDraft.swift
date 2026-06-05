//
//  MCPHeadersDraft.swift
//  UniLLMs
//
//  Represents the editable JSON text for MCP HTTP headers.
//  Created by Codex on 2026/6/5.
//

import Foundation

enum MCPHeadersDraftError: LocalizedError, Equatable {
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return String(localized: .mcpErrorInvalidHeadersJson)
        }
    }
}

enum MCPHeadersDraftResult: Equatable {
    case valid([String: String])
    case invalid(MCPHeadersDraftError)

    var headers: [String: String]? {
        guard case let .valid(headers) = self else {
            return nil
        }
        return headers
    }
}

protocol MCPHeadersJSONCoding {
    func decodeHeaders(from text: String) throws -> [String: String]
    func encodeHeaders(_ headers: [String: String]) throws -> String
}

struct MCPHeadersDraft: Equatable {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(
        headers: [String: String],
        coder: any MCPHeadersJSONCoding = MCPHeadersJSONCoder()
    ) {
        text = Self.text(from: headers, coder: coder)
    }

    func headersResult(coder: any MCPHeadersJSONCoding = MCPHeadersJSONCoder()) -> MCPHeadersDraftResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .valid([:])
        }

        do {
            return .valid(try coder.decodeHeaders(from: trimmedText))
        } catch {
            return .invalid(.invalidJSON)
        }
    }

    func headersForSaving(coder: any MCPHeadersJSONCoding = MCPHeadersJSONCoder()) -> [String: String]? {
        headersResult(coder: coder).headers
    }

    static func text(
        from headers: [String: String],
        coder: any MCPHeadersJSONCoding = MCPHeadersJSONCoder()
    ) -> String {
        guard !headers.isEmpty else {
            return ""
        }

        return (try? coder.encodeHeaders(headers)) ?? ""
    }
}

struct MCPHeadersJSONCoder: MCPHeadersJSONCoding {
    func decodeHeaders(from text: String) throws -> [String: String] {
        guard let data = text.data(using: .utf8) else {
            throw MCPHeadersDraftError.invalidJSON
        }

        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func encodeHeaders(_ headers: [String: String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(headers)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPHeadersDraftError.invalidJSON
        }
        return text
    }
}
