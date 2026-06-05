//
//  ChatContinuationTaskRequestPlanTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatContinuationTaskRequestPlanTests: XCTestCase {
    func testMakeUsesStablePrefixAndDashlessUUIDSuffix() {
        let plan = ChatContinuationTaskRequestPlan.make(
            uuid: UUID(uuidString: "12345678-90AB-CDEF-1234-567890ABCDEF")!
        )

        XCTAssertEqual(
            plan.identifier,
            "Zayrick.UniLLMs.chatTurn.1234567890ABCDEF1234567890ABCDEF"
        )
        XCTAssertEqual(plan.registrationIdentifier, plan.identifier)
        XCTAssertTrue(plan.isPermittedByDefaultPattern)
    }

    func testSuffixInitializerSanitizesToAlphanumericIdentifierSuffix() {
        let plan = ChatContinuationTaskRequestPlan(suffix: " turn-1_测试 ")

        XCTAssertEqual(plan.identifier, "Zayrick.UniLLMs.chatTurn.turn1")
    }

    func testSuffixInitializerFallsBackWhenSuffixHasNoIdentifierCharacters() {
        let plan = ChatContinuationTaskRequestPlan(suffix: " -- _ ")

        XCTAssertTrue(plan.identifier.hasPrefix("Zayrick.UniLLMs.chatTurn."))
        XCTAssertGreaterThan(plan.identifier.count, "Zayrick.UniLLMs.chatTurn.".count)
        XCTAssertTrue(plan.isPermittedByDefaultPattern)
    }

    func testPermittedIdentifierMatchingAcceptsExactAndTrailingWildcardPatterns() {
        let plan = ChatContinuationTaskRequestPlan(suffix: "ABC")

        XCTAssertTrue(plan.isPermitted(by: ["Zayrick.UniLLMs.chatTurn.ABC"]))
        XCTAssertTrue(plan.isPermitted(by: ["Zayrick.UniLLMs.chatTurn.*"]))
        XCTAssertFalse(plan.isPermitted(by: ["Zayrick.UniLLMs.other.*"]))
        XCTAssertFalse(plan.isPermitted(by: ["Zayrick.UniLLMs.chatTurn"]))
    }

    func testPermittedIdentifierPatternMatchesInfoPlistContract() {
        XCTAssertEqual(
            ChatContinuationTaskRequestPlan.permittedIdentifierPattern,
            "Zayrick.UniLLMs.chatTurn.*"
        )
        XCTAssertEqual(
            ChatContinuationTaskRequestPlan.infoPlistPermittedIdentifiersKey,
            "BGTaskSchedulerPermittedIdentifiers"
        )
    }
}
