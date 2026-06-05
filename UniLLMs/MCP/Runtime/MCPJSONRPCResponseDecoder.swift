//
//  MCPJSONRPCResponseDecoder.swift
//  UniLLMs
//
//  Decodes MCP Streamable HTTP JSON-RPC responses from JSON and SSE bodies.
//

import Foundation

nonisolated struct MCPJSONRPCError: Decodable, Equatable {
    var code: Int
    var message: String
    var data: JSONValue?
}

nonisolated struct MCPJSONRPCResponse: Decodable, Equatable {
    var id: JSONValue?
    var result: JSONValue?
    var error: MCPJSONRPCError?

    var isRequestResponse: Bool {
        result != nil || error != nil
    }
}

nonisolated enum MCPJSONRPCResponseDecoder {
    static func decode(
        data: Data,
        contentType: String?,
        serverName: String
    ) throws -> MCPJSONRPCResponse {
        if contentType?.range(of: "text/event-stream", options: .caseInsensitive) != nil {
            return try decodeServerSentEventResponse(data: data, serverName: serverName)
        }

        return try decodeJSONResponse(data, serverName: serverName)
    }

    private static func decodeServerSentEventResponse(
        data: Data,
        serverName: String
    ) throws -> MCPJSONRPCResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPHTTPClientError.invalidResponse(serverName)
        }

        for line in text.components(separatedBy: .newlines) {
            guard let payload = ServerSentEventLine.dataPayload(from: line),
                  !payload.isEmpty else {
                continue
            }
            guard let payloadData = payload.data(using: .utf8) else {
                throw MCPHTTPClientError.invalidResponse(serverName)
            }

            let response: MCPJSONRPCResponse
            do {
                response = try JSONDecoder().decode(MCPJSONRPCResponse.self, from: payloadData)
            } catch {
                throw MCPHTTPClientError.invalidResponse(serverName)
            }

            guard response.isRequestResponse else {
                continue
            }

            return response
        }

        throw MCPHTTPClientError.invalidResponse(serverName)
    }

    private static func decodeJSONResponse(
        _ data: Data,
        serverName: String
    ) throws -> MCPJSONRPCResponse {
        do {
            let response = try JSONDecoder().decode(MCPJSONRPCResponse.self, from: data)
            guard response.isRequestResponse else {
                throw MCPHTTPClientError.invalidResponse(serverName)
            }
            return response
        } catch {
            throw MCPHTTPClientError.invalidResponse(serverName)
        }
    }
}
