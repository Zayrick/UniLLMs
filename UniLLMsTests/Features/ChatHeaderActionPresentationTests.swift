//
//  ChatHeaderActionPresentationTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatHeaderActionPresentationTests: XCTestCase {
    func testEmptyConversationShowsPrivateChatAction() {
        let presentation = ChatHeaderActionPresentation.make(
            isGeneratingResponse: false,
            isPrivateModeEnabled: false,
            hasChatContent: false
        )

        XCTAssertEqual(presentation.iconSystemName, "app.dashed")
        XCTAssertFalse(presentation.showsActivityIndicator)
        XCTAssertFalse(presentation.usesAccentColor)
        XCTAssertFalse(presentation.isSelected)
        XCTAssertEqual(presentation.accessibilityLabel, .privateChat)
        XCTAssertEqual(presentation.accessibilityHint, .privateChatHint)
    }

    func testPrivateEmptyConversationShowsActivePrivateChatAction() {
        let presentation = ChatHeaderActionPresentation.make(
            isGeneratingResponse: false,
            isPrivateModeEnabled: true,
            hasChatContent: false
        )

        XCTAssertEqual(presentation.iconSystemName, "lock.app.dashed")
        XCTAssertFalse(presentation.showsActivityIndicator)
        XCTAssertTrue(presentation.usesAccentColor)
        XCTAssertTrue(presentation.isSelected)
        XCTAssertEqual(presentation.accessibilityLabel, .privateChatActive)
        XCTAssertEqual(presentation.accessibilityHint, .privateChatActiveHint)
    }

    func testConversationWithContentShowsNewChatAction() {
        let presentation = ChatHeaderActionPresentation.make(
            isGeneratingResponse: false,
            isPrivateModeEnabled: true,
            hasChatContent: true
        )

        XCTAssertEqual(presentation.iconSystemName, "plus.message")
        XCTAssertFalse(presentation.showsActivityIndicator)
        XCTAssertFalse(presentation.usesAccentColor)
        XCTAssertFalse(presentation.isSelected)
        XCTAssertEqual(presentation.accessibilityLabel, .newChat)
        XCTAssertNil(presentation.accessibilityHint)
    }

    func testGeneratingResponseShowsActivityState() {
        let presentation = ChatHeaderActionPresentation.make(
            isGeneratingResponse: true,
            isPrivateModeEnabled: false,
            hasChatContent: true
        )

        XCTAssertNil(presentation.iconSystemName)
        XCTAssertTrue(presentation.showsActivityIndicator)
        XCTAssertFalse(presentation.usesAccentColor)
        XCTAssertFalse(presentation.isSelected)
        XCTAssertEqual(presentation.accessibilityLabel, .generatingResponse)
        XCTAssertNil(presentation.accessibilityHint)
    }
}
