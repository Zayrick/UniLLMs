//
//  JSONFileStore.swift
//  UniLLMs
//
//  Provides lightweight JSON file reading and writing for future archive, memory, or chat history storage.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

struct JSONFileStore {
    let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load<Value: Decodable>(_ type: Value.Type, filename: String) throws -> Value {
        let data = try Data(contentsOf: directoryURL.appendingPathComponent(filename))
        return try decoder.decode(type, from: data)
    }

    func save<Value: Encodable>(_ value: Value, filename: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(
            to: directoryURL.appendingPathComponent(filename),
            options: [.atomic]
        )
    }
}
