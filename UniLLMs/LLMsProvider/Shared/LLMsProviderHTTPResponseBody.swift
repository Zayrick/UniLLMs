//
//  LLMsProviderHTTPResponseBody.swift
//  UniLLMs
//
//  Shared helpers for collecting short HTTP error body previews.
//

import Foundation

nonisolated enum LLMsProviderHTTPResponseBody {
    static let defaultCharacterLimit = 2_048

    static func preview(
        from bytes: URLSession.AsyncBytes,
        characterLimit: Int = defaultCharacterLimit
    ) async throws -> String {
        try await preview(from: bytes.lines, characterLimit: characterLimit)
    }

    static func preview<Lines: AsyncSequence>(
        from lines: Lines,
        characterLimit: Int = defaultCharacterLimit
    ) async throws -> String where Lines.Element == String {
        var body = ""
        for try await line in lines {
            if !body.isEmpty {
                body.append("\n")
            }
            body.append(line)
            if body.count > characterLimit {
                break
            }
        }
        return body
    }
}

nonisolated enum LLMsProviderHTTPResponseValidator {
    static func validateDataResponse<Failure: Error>(
        response: URLResponse,
        data: Data,
        serviceName: String,
        invalidResponseError: (String) -> Failure,
        serverStatusError: (String, Int, String?) -> Failure
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw invalidResponseError(serviceName)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw serverStatusError(
                serviceName,
                httpResponse.statusCode,
                String(data: data, encoding: .utf8)
            )
        }
    }

    static func validateStreamingResponse<Failure: Error>(
        response: URLResponse,
        bytes: URLSession.AsyncBytes,
        serviceName: String,
        invalidResponseError: (String) -> Failure,
        serverStatusError: (String, Int, String?) -> Failure
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw invalidResponseError(serviceName)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw serverStatusError(
                serviceName,
                httpResponse.statusCode,
                try await LLMsProviderHTTPResponseBody.preview(from: bytes)
            )
        }
    }
}
