//
//  ServerSentEventJSONDecoder.swift
//  UniLLMs
//
//  Decodes JSON payloads carried by single-line server-sent event data fields.
//

import Foundation

nonisolated enum ServerSentEventJSONDecoder {
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from line: String,
        skipsDoneSignal: Bool = true,
        invalidPayloadError: () -> Error
    ) throws -> Value? {
        guard let payload = ServerSentEventLine.dataPayload(from: line) else {
            return nil
        }

        guard !skipsDoneSignal || payload != "[DONE]" else {
            return nil
        }

        guard let data = payload.data(using: .utf8) else {
            throw invalidPayloadError()
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw invalidPayloadError()
        }
    }
}
