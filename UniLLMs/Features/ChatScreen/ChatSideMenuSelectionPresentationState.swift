//
//  ChatSideMenuSelectionPresentationState.swift
//  UniLLMs
//
//  Tracks confirmed and pending side-menu history selection.
//

import Foundation

nonisolated struct ChatSideMenuSelectionPresentationState: Equatable {
    private(set) var confirmedSessionID: UUID?
    private(set) var pendingSessionID: UUID?

    var displayedSessionID: UUID? {
        pendingSessionID ?? confirmedSessionID
    }

    mutating func applyConfirmedSelection(_ sessionID: UUID?) {
        confirmedSessionID = sessionID
        pendingSessionID = nil
    }

    mutating func beginPendingSelection(_ sessionID: UUID) {
        pendingSessionID = sessionID
    }

    mutating func confirmPendingSelection(_ sessionID: UUID) {
        confirmedSessionID = sessionID
        pendingSessionID = nil
    }

    mutating func rejectPendingSelection() {
        pendingSessionID = nil
    }
}
