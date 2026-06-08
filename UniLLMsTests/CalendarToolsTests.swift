//
//  CalendarToolsTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class CalendarToolsTests: XCTestCase {
    func testCalendarReadToolFetchesEventsInDateRange() async throws {
        let store = StubCalendarEventStore()
        store.eventsToFetch = [
            CalendarEventRecord(
                id: "event-1",
                title: "Planning",
                calendarTitle: "Work",
                startDate: try Self.date("2026-06-08T09:00:00Z"),
                endDate: try Self.date("2026-06-08T10:00:00Z"),
                isAllDay: false,
                notes: "Agenda",
                location: "Office",
                url: URL(string: "https://example.com/meeting")
            )
        ]

        let result = try await CalendarReadTool(eventStore: store).execute(
            call: ToolCall(
                id: "call_read",
                toolID: CalendarToolCatalog.readID,
                arguments: [
                    "start_date": .string("2026-06-08T00:00:00Z"),
                    "end_date": .string("2026-06-09T00:00:00Z"),
                    "limit": .int(10)
                ]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(store.fetchedCriteria?.limit, 10)
        XCTAssertEqual(store.fetchedCriteria?.startDate, try Self.date("2026-06-08T00:00:00Z"))

        let payload = try Self.payload(from: result)
        XCTAssertEqual(payload["count"] as? Int, 1)
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        XCTAssertEqual(events.first?["title"] as? String, "Planning")
        XCTAssertEqual(events.first?["calendar"] as? String, "Work")
    }

    func testCalendarCreateToolCreatesEventDraft() async throws {
        let store = StubCalendarEventStore()
        store.eventToSave = CalendarEventRecord(
            id: "event-2",
            title: "Doctor",
            calendarTitle: "Personal",
            startDate: try Self.date("2026-06-08T15:00:00Z"),
            endDate: try Self.date("2026-06-08T15:30:00Z"),
            isAllDay: false,
            notes: "Bring forms",
            location: "Clinic",
            url: URL(string: "https://example.com/doctor")
        )

        let result = try await CalendarCreateTool(eventStore: store).execute(
            call: ToolCall(
                id: "call_create",
                toolID: CalendarToolCatalog.createID,
                arguments: [
                    "title": .string("Doctor"),
                    "start_date": .string("2026-06-08T15:00:00Z"),
                    "duration_minutes": .int(30),
                    "notes": .string("Bring forms"),
                    "location": .string("Clinic"),
                    "url": .string("https://example.com/doctor")
                ]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertFalse(result.isError)
        let draft = try XCTUnwrap(store.savedDrafts.first)
        XCTAssertEqual(draft.title, "Doctor")
        XCTAssertEqual(draft.startDate, try Self.date("2026-06-08T15:00:00Z"))
        XCTAssertEqual(draft.endDate, try Self.date("2026-06-08T15:30:00Z"))
        XCTAssertEqual(draft.notes, "Bring forms")
        XCTAssertEqual(draft.location, "Clinic")
        XCTAssertEqual(draft.url?.absoluteString, "https://example.com/doctor")

        let payload = try Self.payload(from: result)
        XCTAssertEqual(payload["status"] as? String, "created")
        let event = try XCTUnwrap(payload["event"] as? [String: Any])
        XCTAssertEqual(event["title"] as? String, "Doctor")
    }

    func testCalendarUpdateToolUpdatesEventFields() async throws {
        let store = StubCalendarEventStore()
        store.eventToUpdate = CalendarEventRecord(
            id: "event-3",
            title: "Dentist",
            calendarTitle: "Personal",
            startDate: try Self.date("2026-06-08T16:00:00Z"),
            endDate: try Self.date("2026-06-08T17:00:00Z"),
            isAllDay: false,
            notes: nil,
            location: "New Clinic",
            url: nil
        )

        let result = try await CalendarUpdateTool(eventStore: store).execute(
            call: ToolCall(
                id: "call_update",
                toolID: CalendarToolCatalog.updateID,
                arguments: [
                    "id": .string("event-3"),
                    "title": .string("Dentist"),
                    "start_date": .string("2026-06-08T16:00:00Z"),
                    "end_date": .string("2026-06-08T17:00:00Z"),
                    "location": .string("New Clinic"),
                    "clear_notes": .bool(true)
                ]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertFalse(result.isError)
        let update = try XCTUnwrap(store.updates.first)
        XCTAssertEqual(update.id, "event-3")
        XCTAssertEqual(update.title, "Dentist")
        XCTAssertEqual(update.startDate, try Self.date("2026-06-08T16:00:00Z"))
        XCTAssertEqual(update.endDate, try Self.date("2026-06-08T17:00:00Z"))
        XCTAssertEqual(update.location, "New Clinic")
        XCTAssertTrue(update.clearsNotes)

        let payload = try Self.payload(from: result)
        XCTAssertEqual(payload["status"] as? String, "updated")
    }

    func testCalendarDeleteToolDeletesEventByID() async throws {
        let store = StubCalendarEventStore()
        store.eventToDelete = CalendarEventRecord(
            id: "event-4",
            title: "Canceled",
            calendarTitle: "Personal",
            startDate: try Self.date("2026-06-08T18:00:00Z"),
            endDate: try Self.date("2026-06-08T19:00:00Z"),
            isAllDay: false,
            notes: nil,
            location: nil,
            url: nil
        )

        let result = try await CalendarDeleteTool(eventStore: store).execute(
            call: ToolCall(
                id: "call_delete",
                toolID: CalendarToolCatalog.deleteID,
                arguments: ["id": .string("event-4")]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(store.deletedIDs, ["event-4"])

        let payload = try Self.payload(from: result)
        XCTAssertEqual(payload["status"] as? String, "deleted")
    }

    func testCalendarReadToolRejectsInvalidDateRange() async throws {
        let store = StubCalendarEventStore()

        let result = try await CalendarReadTool(eventStore: store).execute(
            call: ToolCall(
                id: "call_read",
                toolID: CalendarToolCatalog.readID,
                arguments: [
                    "start_date": .string("2026-06-09T00:00:00Z"),
                    "end_date": .string("2026-06-08T00:00:00Z")
                ]
            ),
            context: ToolExecutionContext(session: nil)
        )

        XCTAssertTrue(result.isError)
        XCTAssertNil(store.fetchedCriteria)
        XCTAssertTrue(result.content.contains("end_date"))
    }

    fileprivate static func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    private static func payload(from result: ToolResult) throws -> [String: Any] {
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
private final class StubCalendarEventStore: CalendarEventStore {
    var fetchedCriteria: CalendarReadCriteria?
    var eventsToFetch: [CalendarEventRecord] = []
    var savedDrafts: [CalendarEventDraft] = []
    var eventToSave: CalendarEventRecord?
    var updates: [CalendarEventUpdate] = []
    var eventToUpdate: CalendarEventRecord?
    var deletedIDs: [String] = []
    var eventToDelete: CalendarEventRecord?

    func fetchEvents(criteria: CalendarReadCriteria) async throws -> [CalendarEventRecord] {
        fetchedCriteria = criteria
        return eventsToFetch
    }

    func saveEvent(draft: CalendarEventDraft) async throws -> CalendarEventRecord {
        savedDrafts.append(draft)
        if let eventToSave {
            return eventToSave
        }

        return CalendarEventRecord(
            id: "created",
            title: draft.title,
            calendarTitle: nil,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            notes: draft.notes,
            location: draft.location,
            url: draft.url
        )
    }

    func updateEvent(update: CalendarEventUpdate) async throws -> CalendarEventRecord {
        updates.append(update)
        if let eventToUpdate {
            return eventToUpdate
        }

        let startDate: Date
        if let updateStartDate = update.startDate {
            startDate = updateStartDate
        } else {
            startDate = try CalendarToolsTests.date("2026-06-08T00:00:00Z")
        }
        let endDate: Date
        if let updateEndDate = update.endDate {
            endDate = updateEndDate
        } else {
            endDate = try CalendarToolsTests.date("2026-06-08T01:00:00Z")
        }
        return CalendarEventRecord(
            id: update.id,
            title: update.title ?? "Updated",
            calendarTitle: nil,
            startDate: startDate,
            endDate: endDate,
            isAllDay: update.isAllDay ?? false,
            notes: update.notes,
            location: update.location,
            url: update.url
        )
    }

    func deleteEvent(id: String) async throws -> CalendarEventRecord {
        deletedIDs.append(id)
        if let eventToDelete {
            return eventToDelete
        }

        return CalendarEventRecord(
            id: id,
            title: "Deleted",
            calendarTitle: nil,
            startDate: try CalendarToolsTests.date("2026-06-08T00:00:00Z"),
            endDate: try CalendarToolsTests.date("2026-06-08T01:00:00Z"),
            isAllDay: false,
            notes: nil,
            location: nil,
            url: nil
        )
    }
}
