//
//  EntityIDTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class EntityIDTests: XCTestCase {
    @MainActor
    func testInitializerUsesProvidedUUID() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

        let id = EntityID<TestOwner>(uuid)

        XCTAssertEqual(id.rawValue, uuid)
    }

    @MainActor
    func testDefaultInitializerGeneratesDistinctIDs() {
        let first = EntityID<TestOwner>()
        let second = EntityID<TestOwner>()

        XCTAssertNotEqual(first, second)
    }

    @MainActor
    func testCodableRoundTripPreservesRawValue() throws {
        let id = EntityID<TestOwner>()

        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(EntityID<TestOwner>.self, from: data)

        XCTAssertEqual(decoded, id)
    }

    @MainActor
    func testHashableDeduplicatesSameOwnerAndRawValue() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = EntityID<TestOwner>(uuid)
        let second = EntityID<TestOwner>(uuid)

        XCTAssertEqual(Set([first, second]).count, 1)
    }
}

private struct TestOwner {}
