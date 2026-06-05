//
//  ChatSessionHistoryListTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class ChatSessionHistoryListTests: XCTestCase {
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDownWithError() throws {
        calendar = nil
        try super.tearDownWithError()
    }

    func testHistoryListGroupsByUpdatedDayAndSortsMostRecentSessionsFirst() throws {
        let morningSession = makeSession(
            title: "Morning",
            createdAt: makeDate(day: 10, hour: 8),
            updatedAt: makeDate(day: 12, hour: 9)
        )
        let laterCreatedSession = makeSession(
            title: "Later Created",
            createdAt: makeDate(day: 10, hour: 10),
            updatedAt: makeDate(day: 12, hour: 9)
        )
        let yesterdaySession = makeSession(
            title: "Yesterday",
            createdAt: makeDate(day: 11, hour: 8),
            updatedAt: makeDate(day: 11, hour: 23)
        )

        let list = ChatSessionHistoryList(
            sessions: [yesterdaySession, morningSession, laterCreatedSession],
            calendar: calendar
        )

        XCTAssertEqual(list.sections.map(\.date), [
            makeDate(day: 12, hour: 0),
            makeDate(day: 11, hour: 0)
        ])
        XCTAssertEqual(list.sections[0].sessions.map(\.id), [
            laterCreatedSession.id,
            morningSession.id
        ])
        XCTAssertEqual(list.sections[1].sessions.map(\.id), [yesterdaySession.id])
    }

    func testHistoryListFiltersCaseInsensitivelyAndTrimsQueryWhitespace() {
        let alphaSession = makeSession(title: "Alpha Research", updatedAt: makeDate(day: 12, hour: 9))
        let betaSession = makeSession(title: "Beta Notes", updatedAt: makeDate(day: 12, hour: 10))

        let list = ChatSessionHistoryList(
            sessions: [alphaSession, betaSession],
            query: "  alpha  ",
            calendar: calendar
        )

        XCTAssertEqual(list.sections.count, 1)
        XCTAssertEqual(list.sections[0].sessions.map(\.id), [alphaSession.id])
    }

    func testFilteredHistoryListKeepsTieBreakerOrdering() {
        let earlierCreatedSession = makeSession(
            title: "Project early",
            createdAt: makeDate(day: 10, hour: 8),
            updatedAt: makeDate(day: 12, hour: 9)
        )
        let laterCreatedSession = makeSession(
            title: "Project late",
            createdAt: makeDate(day: 10, hour: 10),
            updatedAt: makeDate(day: 12, hour: 9)
        )

        let list = ChatSessionHistoryList(
            sortedSessions: ChatSessionHistoryList.sortedSessions([
                earlierCreatedSession,
                laterCreatedSession
            ]),
            query: "project",
            calendar: calendar
        )

        XCTAssertEqual(list.sections[0].sessions.map(\.id), [
            laterCreatedSession.id,
            earlierCreatedSession.id
        ])
    }

    func testHistoryListFindsSessionPositionWithinFilteredSections() throws {
        let selectedSession = makeSession(title: "Target", updatedAt: makeDate(day: 12, hour: 9))
        let otherSession = makeSession(title: "Other", updatedAt: makeDate(day: 11, hour: 9))
        let list = ChatSessionHistoryList(
            sessions: [otherSession, selectedSession],
            calendar: calendar
        )

        XCTAssertEqual(
            list.position(for: selectedSession.id),
            ChatSessionHistoryList.Position(section: 0, row: 0)
        )
        XCTAssertNil(list.position(for: UUID()))
    }

    func testHistoryListReportsEmptyWhenFilterMatchesNoSessions() {
        let session = makeSession(title: "Alpha", updatedAt: makeDate(day: 12, hour: 9))
        let list = ChatSessionHistoryList(
            sessions: [session],
            query: "missing",
            calendar: calendar
        )

        XCTAssertTrue(list.isEmpty)
        XCTAssertTrue(list.sections.isEmpty)
    }

    private func makeSession(
        id: UUID = UUID(),
        title: String,
        createdAt: Date? = nil,
        updatedAt: Date
    ) -> ChatSession {
        ChatSession(
            id: id,
            title: title,
            createdAt: createdAt ?? updatedAt,
            updatedAt: updatedAt
        )
    }

    private func makeDate(day: Int, hour: Int) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 6,
                day: day,
                hour: hour
            )
        )!
    }
}
