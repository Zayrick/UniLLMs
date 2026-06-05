//
//  UserDefaultsStoreTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class UserDefaultsStoreTests: UserDefaultsBackedTestCase {
    func testLoadResultDistinguishesMissingLoadedAndFailedValues() {
        var failures: [UserDefaultsStoreFailure] = []
        let store = UserDefaultsStore(defaults: defaults) { failure in
            failures.append(failure)
        }

        XCTAssertLoadResultMissing(store.loadResult(PersistedCounter.self, forKey: "counter"))

        XCTAssertTrue(store.save(PersistedCounter(count: 4), forKey: "counter"))
        XCTAssertLoadResultLoaded(
            store.loadResult(PersistedCounter.self, forKey: "counter"),
            expected: PersistedCounter(count: 4)
        )

        defaults.set(Data("not-json".utf8), forKey: "counter")

        XCTAssertLoadResultFailed(store.loadResult(PersistedCounter.self, forKey: "counter"))
        XCTAssertEqual(failures.map(\.operation), [.load])
        XCTAssertEqual(failures.map(\.key), ["counter"])
        XCTAssertEqual(failures.map(\.typeName), ["PersistedCounter"])
    }

    func testLoadReportsDecodeFailureAndPreservesOptionalFallback() {
        var failures: [UserDefaultsStoreFailure] = []
        let store = UserDefaultsStore(defaults: defaults) { failure in
            failures.append(failure)
        }
        defaults.set(Data("not-json".utf8), forKey: "counter")

        XCTAssertNil(store.load(PersistedCounter.self, forKey: "counter"))

        XCTAssertEqual(failures.map(\.operation), [.load])
        XCTAssertEqual(failures.first?.key, "counter")
    }

    func testFailuresPostNotification() {
        let notificationCenter = NotificationCenter()
        let store = UserDefaultsStore(
            defaults: defaults,
            notificationCenter: notificationCenter
        )
        var notificationFailures: [UserDefaultsStoreFailure] = []
        let observer = notificationCenter.addObserver(
            forName: UserDefaultsStore.didFailNotification,
            object: store,
            queue: nil
        ) { notification in
            if let failure = notification.userInfo?[UserDefaultsStore.failureUserInfoKey] as? UserDefaultsStoreFailure {
                notificationFailures.append(failure)
            }
        }
        defer {
            notificationCenter.removeObserver(observer)
        }
        defaults.set(Data("not-json".utf8), forKey: "counter")

        XCTAssertNil(store.load(PersistedCounter.self, forKey: "counter"))

        XCTAssertEqual(notificationFailures.map(\.operation), [.load])
        XCTAssertEqual(notificationFailures.first?.key, "counter")
    }

    func testSaveReportsEncodingFailureWithoutWritingValue() {
        var failures: [UserDefaultsStoreFailure] = []
        let store = UserDefaultsStore(defaults: defaults) { failure in
            failures.append(failure)
        }

        let didSave = store.save(ThrowingPersistedValue(), forKey: "broken")

        XCTAssertFalse(didSave)
        XCTAssertFalse(store.containsValue(forKey: "broken"))
        XCTAssertEqual(failures.map(\.operation), [.save])
        XCTAssertEqual(failures.first?.key, "broken")
        XCTAssertEqual(failures.first?.typeName, "ThrowingPersistedValue")
    }

    func testSaveOrThrowReportsAndThrowsEncodingFailureWithoutWritingValue() {
        var failures: [UserDefaultsStoreFailure] = []
        let store = UserDefaultsStore(defaults: defaults) { failure in
            failures.append(failure)
        }

        XCTAssertThrowsError(try store.saveOrThrow(ThrowingPersistedValue(), forKey: "broken")) { error in
            let failure = error as? UserDefaultsStoreFailure
            XCTAssertEqual(failure?.operation, .save)
            XCTAssertEqual(failure?.key, "broken")
            XCTAssertEqual(failure?.typeName, "ThrowingPersistedValue")
        }

        XCTAssertFalse(store.containsValue(forKey: "broken"))
        XCTAssertEqual(failures.map(\.operation), [.save])
        XCTAssertEqual(failures.first?.key, "broken")
    }

    func testSaveReplacingPersistsChangedValueAndCallsDidSave() {
        let store = UserDefaultsStore(defaults: defaults)
        var didSaveCount = 0

        let didSave = store.save(
            PersistedCounter(count: 2),
            replacing: PersistedCounter(count: 1),
            forKey: "counter"
        ) {
            didSaveCount += 1
        }

        XCTAssertTrue(didSave)
        XCTAssertEqual(didSaveCount, 1)
        XCTAssertEqual(store.load(PersistedCounter.self, forKey: "counter"), PersistedCounter(count: 2))
    }

    func testSaveReplacingSkipsUnchangedValueAndDidSave() {
        let store = UserDefaultsStore(defaults: defaults)
        var didSaveCount = 0

        let didSave = store.save(
            PersistedCounter(count: 1),
            replacing: PersistedCounter(count: 1),
            forKey: "counter"
        ) {
            didSaveCount += 1
        }

        XCTAssertFalse(didSave)
        XCTAssertEqual(didSaveCount, 0)
        XCTAssertNil(store.load(PersistedCounter.self, forKey: "counter"))
    }

    func testUpdateLoadsDefaultMutatesAndCallsDidSaveOnlyWhenChanged() {
        let store = UserDefaultsStore(defaults: defaults)
        var didSaveCount = 0

        let updated = store.update(PersistedCounter.self, forKey: "counter", defaultValue: PersistedCounter()) { counter in
            counter.count += 1
        } didSave: {
            didSaveCount += 1
        }
        let unchanged = store.update(PersistedCounter.self, forKey: "counter", defaultValue: PersistedCounter()) { _ in
        } didSave: {
            didSaveCount += 1
        }

        XCTAssertEqual(updated, PersistedCounter(count: 1))
        XCTAssertEqual(unchanged, PersistedCounter(count: 1))
        XCTAssertEqual(didSaveCount, 1)
        XCTAssertEqual(store.load(PersistedCounter.self, forKey: "counter"), PersistedCounter(count: 1))
    }

    func testUpdateReportsDecodeFailureThenMutatesDefaultValue() {
        var failures: [UserDefaultsStoreFailure] = []
        let store = UserDefaultsStore(defaults: defaults) { failure in
            failures.append(failure)
        }
        defaults.set(Data("not-json".utf8), forKey: "counter")

        let updated = store.update(PersistedCounter.self, forKey: "counter", defaultValue: PersistedCounter()) { counter in
            counter.count += 3
        }

        XCTAssertEqual(updated, PersistedCounter(count: 3))
        XCTAssertEqual(store.load(PersistedCounter.self, forKey: "counter"), PersistedCounter(count: 3))
        XCTAssertEqual(failures.map(\.operation), [.load])
    }

    func testUpdateRepairsDecodeFailureEvenWhenMutationDoesNotChangeDefaultValue() {
        var failures: [UserDefaultsStoreFailure] = []
        let store = UserDefaultsStore(defaults: defaults) { failure in
            failures.append(failure)
        }
        var didSaveCount = 0
        defaults.set(Data("not-json".utf8), forKey: "counter")

        let updated = store.update(PersistedCounter.self, forKey: "counter", defaultValue: PersistedCounter()) { _ in
        } didSave: {
            didSaveCount += 1
        }

        failures.removeAll()
        XCTAssertEqual(updated, PersistedCounter())
        XCTAssertEqual(didSaveCount, 1)
        XCTAssertEqual(store.load(PersistedCounter.self, forKey: "counter"), PersistedCounter())
        XCTAssertTrue(failures.isEmpty)
    }

    func testUpdateOrThrowReportsAndThrowsSaveFailure() {
        var failures: [UserDefaultsStoreFailure] = []
        let store = UserDefaultsStore(defaults: defaults) { failure in
            failures.append(failure)
        }
        var didSaveCount = 0

        XCTAssertThrowsError(
            try store.updateOrThrow(
                ThrowingCodableCounter.self,
                forKey: "counter",
                defaultValue: ThrowingCodableCounter()
            ) { counter in
                counter.count += 1
            } didSave: {
                didSaveCount += 1
            }
        ) { error in
            let failure = error as? UserDefaultsStoreFailure
            XCTAssertEqual(failure?.operation, .save)
            XCTAssertEqual(failure?.key, "counter")
            XCTAssertEqual(failure?.typeName, "ThrowingCodableCounter")
        }

        XCTAssertEqual(didSaveCount, 0)
        XCTAssertFalse(store.containsValue(forKey: "counter"))
        XCTAssertEqual(failures.map(\.operation), [.save])
    }

    func testStoreFailureProvidesLocalizedDescription() {
        let loadFailure = UserDefaultsStoreFailure(
            operation: .load,
            key: "broken",
            typeName: "PersistedCounter",
            error: ThrowingPersistedValueError.failed
        )
        let saveFailure = UserDefaultsStoreFailure(
            operation: .save,
            key: "broken",
            typeName: "PersistedCounter",
            error: ThrowingPersistedValueError.failed
        )

        XCTAssertEqual(loadFailure.localizedDescription, String(localized: .storageUserDefaultsLoadFailed))
        XCTAssertEqual(saveFailure.localizedDescription, String(localized: .storageUserDefaultsSaveFailed))
    }

    func testContainsValueTracksRawStoredDataAndRemoval() throws {
        let store = UserDefaultsStore(defaults: defaults)

        XCTAssertFalse(store.containsValue(forKey: "counter"))

        defaults.set(Data("not-json".utf8), forKey: "counter")

        XCTAssertTrue(store.containsValue(forKey: "counter"))

        store.removeValue(forKey: "counter")

        XCTAssertFalse(store.containsValue(forKey: "counter"))
    }
}

private struct PersistedCounter: Codable, Equatable {
    var count = 0
}

private struct ThrowingPersistedValue: Encodable {
    func encode(to encoder: Encoder) throws {
        throw ThrowingPersistedValueError.failed
    }
}

private struct ThrowingCodableCounter: Codable, Equatable {
    var count = 0

    init(count: Int = 0) {
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        count = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        throw ThrowingPersistedValueError.failed
    }
}

private enum ThrowingPersistedValueError: Error {
    case failed
}

private func XCTAssertLoadResultMissing<Value>(
    _ result: UserDefaultsStoreLoadResult<Value>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .missing = result else {
        XCTFail("Expected missing load result.", file: file, line: line)
        return
    }
}

private func XCTAssertLoadResultLoaded<Value: Equatable>(
    _ result: UserDefaultsStoreLoadResult<Value>,
    expected: Value,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case let .loaded(value) = result else {
        XCTFail("Expected loaded load result.", file: file, line: line)
        return
    }

    XCTAssertEqual(value, expected, file: file, line: line)
}

private func XCTAssertLoadResultFailed<Value>(
    _ result: UserDefaultsStoreLoadResult<Value>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .failed = result else {
        XCTFail("Expected failed load result.", file: file, line: line)
        return
    }
}
