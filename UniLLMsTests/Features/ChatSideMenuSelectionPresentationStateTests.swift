//
//  ChatSideMenuSelectionPresentationStateTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatSideMenuSelectionPresentationStateTests: XCTestCase {
    func testPendingSelectionOverridesDisplayedConfirmedSelection() {
        let confirmedID = UUID()
        let pendingID = UUID()
        var state = ChatSideMenuSelectionPresentationState()

        state.applyConfirmedSelection(confirmedID)
        state.beginPendingSelection(pendingID)

        XCTAssertEqual(state.confirmedSessionID, confirmedID)
        XCTAssertEqual(state.pendingSessionID, pendingID)
        XCTAssertEqual(state.displayedSessionID, pendingID)
    }

    func testRejectPendingSelectionRevertsDisplayedSelectionToConfirmedSelection() {
        let confirmedID = UUID()
        var state = ChatSideMenuSelectionPresentationState()

        state.applyConfirmedSelection(confirmedID)
        state.beginPendingSelection(UUID())
        state.rejectPendingSelection()

        XCTAssertEqual(state.confirmedSessionID, confirmedID)
        XCTAssertNil(state.pendingSessionID)
        XCTAssertEqual(state.displayedSessionID, confirmedID)
    }

    func testConfirmedSelectionClearsPendingSelection() {
        let confirmedID = UUID()
        var state = ChatSideMenuSelectionPresentationState()

        state.beginPendingSelection(UUID())
        state.applyConfirmedSelection(confirmedID)

        XCTAssertEqual(state.confirmedSessionID, confirmedID)
        XCTAssertNil(state.pendingSessionID)
        XCTAssertEqual(state.displayedSessionID, confirmedID)
    }

    func testConfirmPendingSelectionPromotesSelectionToConfirmed() {
        let pendingID = UUID()
        var state = ChatSideMenuSelectionPresentationState()

        state.applyConfirmedSelection(UUID())
        state.beginPendingSelection(pendingID)
        state.confirmPendingSelection(pendingID)

        XCTAssertEqual(state.confirmedSessionID, pendingID)
        XCTAssertNil(state.pendingSessionID)
        XCTAssertEqual(state.displayedSessionID, pendingID)
    }
}
