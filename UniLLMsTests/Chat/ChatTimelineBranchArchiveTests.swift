//
//  ChatTimelineBranchArchiveTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatTimelineBranchArchiveTests: XCTestCase {
    func testArchiveSplitsMainlineAtAnchorAndRetainsRevisionEvents() throws {
        let firstUser = event(id: UUID(), kind: .userMessage(text: "First"))
        let firstAssistant = event(kind: .assistantContent(markdown: "First response"))
        let anchorUser = event(id: UUID(), kind: .userMessage(text: "Second"))
        let secondAssistant = event(kind: .assistantContent(markdown: "Second response"))
        let revision = revisionEvent(anchorUserMessageID: anchorUser.id)

        let archive = try XCTUnwrap(
            ChatTimelineBranchArchive.make(
                from: [
                    firstUser,
                    firstAssistant,
                    revision,
                    anchorUser,
                    secondAssistant
                ],
                anchoredAt: anchorUser.id
            )
        )

        XCTAssertEqual(archive.prefixMainlineEvents, [firstUser, firstAssistant])
        XCTAssertEqual(archive.currentBranchEvents, [anchorUser, secondAssistant])
        XCTAssertEqual(archive.retainedRevisionEvents, [revision])
    }

    func testArchiveExcludesSelectedRevisionEvent() throws {
        let anchorUser = event(id: UUID(), kind: .userMessage(text: "Second"))
        let selectedRevision = revisionEvent(anchorUserMessageID: anchorUser.id)
        let retainedRevision = revisionEvent(anchorUserMessageID: anchorUser.id)
        let selectedRevisionID = selectedRevision.revisionID

        let archive = try XCTUnwrap(
            ChatTimelineBranchArchive.make(
                from: [selectedRevision, retainedRevision, anchorUser],
                anchoredAt: anchorUser.id,
                excludingRevisionID: selectedRevisionID
            )
        )

        XCTAssertEqual(archive.retainedRevisionEvents, [retainedRevision])
    }

    func testArchiveIgnoresRevisionEventsWhenBuildingCurrentBranch() throws {
        let anchorUser = event(id: UUID(), kind: .userMessage(text: "Second"))
        let revision = revisionEvent(anchorUserMessageID: anchorUser.id)
        let assistant = event(kind: .assistantContent(markdown: "Second response"))

        let archive = try XCTUnwrap(
            ChatTimelineBranchArchive.make(
                from: [anchorUser, revision, assistant],
                anchoredAt: anchorUser.id
            )
        )

        XCTAssertEqual(archive.currentBranchEvents, [anchorUser, assistant])
    }

    func testArchiveRequiresAnchorToBeUserMessage() {
        let assistantID = UUID()
        let assistant = event(
            id: assistantID,
            kind: .assistantContent(markdown: "Assistant")
        )

        XCTAssertNil(
            ChatTimelineBranchArchive.make(
                from: [assistant],
                anchoredAt: assistantID
            )
        )
    }

    private func event(
        id: UUID = UUID(),
        kind: ChatTimelineEvent.Kind
    ) -> ChatTimelineEvent {
        ChatTimelineEvent(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1),
            kind: kind
        )
    }

    private func revisionEvent(anchorUserMessageID: UUID) -> ChatTimelineEvent {
        let revision = ChatMessageRevision(
            anchorUserMessageID: anchorUserMessageID,
            archivedAt: Date(timeIntervalSince1970: 1),
            events: [
                event(kind: .userMessage(text: "Archived"))
            ]
        )
        return event(kind: .messageRevision(revision))
    }
}

private extension ChatTimelineEvent {
    var revisionID: UUID? {
        guard case let .messageRevision(revision) = kind else {
            return nil
        }

        return revision.id
    }
}
