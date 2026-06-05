//
//  UserDefaultsStore.swift
//  UniLLMs
//
//  Encapsulates Codable and UserDefaults read-write details for lightweight configuration persistence.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

struct UserDefaultsStoreFailure: LocalizedError {
    enum Operation: Equatable {
        case load
        case save
    }

    var operation: Operation
    var key: String
    var typeName: String
    var error: Error

    var errorDescription: String? {
        switch operation {
        case .load:
            return String(localized: .storageUserDefaultsLoadFailed)
        case .save:
            return String(localized: .storageUserDefaultsSaveFailed)
        }
    }
}

enum UserDefaultsStoreLoadResult<Value> {
    case missing
    case loaded(Value)
    case failed(UserDefaultsStoreFailure)
}

private struct UserDefaultsStoreUpdateDraft<Value> {
    var value: Value
    var previousValue: Value
    var shouldRepairStoredValue: Bool
}

final class UserDefaultsStore {
    static let didFailNotification = Notification.Name("UserDefaultsStoreDidFail")
    static let failureUserInfoKey = "failure"

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let didFail: (UserDefaultsStoreFailure) -> Void

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        didFail: @escaping (UserDefaultsStoreFailure) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.didFail = didFail
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadResult<Value: Decodable>(_ type: Value.Type, forKey key: String) -> UserDefaultsStoreLoadResult<Value> {
        guard let data = defaults.data(forKey: key) else {
            return .missing
        }

        do {
            return .loaded(try decoder.decode(type, from: data))
        } catch {
            let failure = makeFailure(operation: .load, key: key, type: type, error: error)
            reportFailure(failure)
            return .failed(failure)
        }
    }

    func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard case let .loaded(value) = loadResult(type, forKey: key) else {
            return nil
        }

        return value
    }

    func containsValue(forKey key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }

    @discardableResult
    func save<Value: Encodable>(_ value: Value, forKey key: String) -> Bool {
        do {
            try saveOrThrow(value, forKey: key)
            return true
        } catch {
            return false
        }
    }

    func saveOrThrow<Value: Encodable>(_ value: Value, forKey key: String) throws {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            let failure = makeFailure(operation: .save, key: key, type: Value.self, error: error)
            reportFailure(failure)
            throw failure
        }

        defaults.set(data, forKey: key)
    }

    @discardableResult
    func save<Value: Encodable & Equatable>(
        _ value: Value,
        replacing previousValue: Value,
        forKey key: String,
        didSave: () -> Void = {}
    ) -> Bool {
        guard value != previousValue else {
            return false
        }

        guard save(value, forKey: key) else {
            return false
        }

        didSave()
        return true
    }

    @discardableResult
    func saveOrThrow<Value: Encodable & Equatable>(
        _ value: Value,
        replacing previousValue: Value,
        forKey key: String,
        didSave: () -> Void = {}
    ) throws -> Bool {
        guard value != previousValue else {
            return false
        }

        try saveOrThrow(value, forKey: key)
        didSave()
        return true
    }

    @discardableResult
    func update<Value: Codable & Equatable>(
        _ type: Value.Type,
        forKey key: String,
        defaultValue: @autoclosure () -> Value,
        mutate: (inout Value) -> Void,
        didSave: () -> Void = {}
    ) -> Value {
        let draft = makeUpdateDraft(
            type,
            forKey: key,
            defaultValue: defaultValue,
            mutate: mutate
        )

        if draft.shouldRepairStoredValue {
            if save(draft.value, forKey: key) {
                didSave()
            }
            return draft.value
        }

        save(draft.value, replacing: draft.previousValue, forKey: key, didSave: didSave)
        return draft.value
    }

    @discardableResult
    func updateOrThrow<Value: Codable & Equatable>(
        _ type: Value.Type,
        forKey key: String,
        defaultValue: @autoclosure () -> Value,
        mutate: (inout Value) -> Void,
        didSave: () -> Void = {}
    ) throws -> Value {
        let draft = makeUpdateDraft(
            type,
            forKey: key,
            defaultValue: defaultValue,
            mutate: mutate
        )

        if draft.shouldRepairStoredValue {
            try saveOrThrow(draft.value, forKey: key)
            didSave()
            return draft.value
        }

        try saveOrThrow(draft.value, replacing: draft.previousValue, forKey: key, didSave: didSave)
        return draft.value
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    private func makeUpdateDraft<Value: Decodable & Equatable>(
        _ type: Value.Type,
        forKey key: String,
        defaultValue: () -> Value,
        mutate: (inout Value) -> Void
    ) -> UserDefaultsStoreUpdateDraft<Value> {
        var value: Value
        var shouldRepairStoredValue = false
        switch loadResult(type, forKey: key) {
        case let .loaded(loadedValue):
            value = loadedValue
        case .missing:
            value = defaultValue()
        case .failed:
            value = defaultValue()
            shouldRepairStoredValue = true
        }
        let previousValue = value
        mutate(&value)

        return UserDefaultsStoreUpdateDraft(
            value: value,
            previousValue: previousValue,
            shouldRepairStoredValue: shouldRepairStoredValue
        )
    }

    private func reportFailure(_ failure: UserDefaultsStoreFailure) {
        didFail(failure)
        notificationCenter.post(
            name: Self.didFailNotification,
            object: self,
            userInfo: [Self.failureUserInfoKey: failure]
        )
    }

    private func makeFailure<Value>(
        operation: UserDefaultsStoreFailure.Operation,
        key: String,
        type: Value.Type,
        error: Error
    ) -> UserDefaultsStoreFailure {
        UserDefaultsStoreFailure(
            operation: operation,
            key: key,
            typeName: String(describing: type),
            error: error
        )
    }
}
