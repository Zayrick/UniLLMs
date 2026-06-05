//
//  ChatHeaderActionPolicyTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatHeaderActionPolicyTests: XCTestCase {
    func testActiveResponseIgnoresHeaderAction() {
        XCTAssertEqual(
            ChatHeaderActionPolicy.action(
                isResponseActive: true,
                hasChatContent: true
            ),
            .ignore
        )
        XCTAssertEqual(
            ChatHeaderActionPolicy.action(
                isResponseActive: true,
                hasChatContent: false
            ),
            .ignore
        )
    }

    func testHeaderActionStartsNewConversationWhenContentExists() {
        XCTAssertEqual(
            ChatHeaderActionPolicy.action(
                isResponseActive: false,
                hasChatContent: true
            ),
            .startNewConversation
        )
    }

    func testHeaderActionTogglesPrivacyModeWhenConversationIsEmpty() {
        XCTAssertEqual(
            ChatHeaderActionPolicy.action(
                isResponseActive: false,
                hasChatContent: false
            ),
            .togglePrivacyMode
        )
    }

}
