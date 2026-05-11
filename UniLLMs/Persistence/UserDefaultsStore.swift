//
//  UserDefaultsStore.swift
//  UniLLMs
//
//  Encapsulates Codable and UserDefaults read-write details for lightweight configuration persistence.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class UserDefaultsStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(type, from: data)
    }

    func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
