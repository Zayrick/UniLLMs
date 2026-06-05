//
//  SentMessageBubbleActionMenuPolicyTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class SentMessageBubbleActionMenuPolicyTests: XCTestCase {
    func testMakeItemsOmitsHistoryWhenThereAreNoRevisions() {
        let items = SentMessageBubbleActionMenuPolicy.makeItems(editHistoryCount: 0)

        XCTAssertEqual(items.map(\.action), [.copy, .resend, .editAndResend])
        XCTAssertEqual(items.map(\.systemImageName), ["doc.on.doc", "arrow.clockwise", "square.and.pencil"])
    }

    func testMakeItemsUsesPlainHistoryTitleForSingleRevision() {
        let items = SentMessageBubbleActionMenuPolicy.makeItems(editHistoryCount: 1)

        XCTAssertEqual(items.map(\.action), [.copy, .resend, .editAndResend, .showHistory])
        XCTAssertEqual(items.last?.title, String(localized: .generalHistory))
        XCTAssertEqual(items.last?.systemImageName, "clock")
    }

    func testMakeItemsUsesCountedHistoryTitleForMultipleRevisions() {
        let items = SentMessageBubbleActionMenuPolicy.makeItems(editHistoryCount: 3)

        XCTAssertEqual(items.last?.title, String(localized: .chatHistoryCountFormat(3)))
    }
}
