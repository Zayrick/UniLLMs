//
//  CalendarTools.swift
//  UniLLMs
//
//  Built-in tools that let a model manage calendar events when the user asks.
//

import EventKit
import Foundation

nonisolated enum CalendarToolCatalog {
    static let createID = "calendar_create"
    static let readID = "calendar_read"
    static let updateID = "calendar_update"
    static let deleteID = "calendar_delete"

    static let toolIDs = [
        createID,
        readID,
        updateID,
        deleteID
    ]

    static func containsTool(id: String) -> Bool {
        toolIDs.contains(id)
    }
}

nonisolated struct CalendarReadCriteria: Equatable {
    var startDate: Date
    var endDate: Date
    var limit: Int
}

nonisolated struct CalendarEventDraft: Equatable {
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String?
    var location: String?
    var url: URL?
}

nonisolated struct CalendarEventRecord: Equatable {
    var id: String?
    var title: String
    var calendarTitle: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String?
    var location: String?
    var url: URL?
}

nonisolated struct CalendarEventUpdate: Equatable {
    var id: String
    var title: String?
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool?
    var notes: String?
    var location: String?
    var url: URL?
    var clearsNotes: Bool
    var clearsLocation: Bool
    var clearsURL: Bool

    var hasChanges: Bool {
        title != nil
            || startDate != nil
            || endDate != nil
            || isAllDay != nil
            || notes != nil
            || location != nil
            || url != nil
            || clearsNotes
            || clearsLocation
            || clearsURL
    }
}

protocol CalendarEventStore {
    @MainActor func fetchEvents(criteria: CalendarReadCriteria) async throws -> [CalendarEventRecord]
    @MainActor func saveEvent(draft: CalendarEventDraft) async throws -> CalendarEventRecord
    @MainActor func updateEvent(update: CalendarEventUpdate) async throws -> CalendarEventRecord
    @MainActor func deleteEvent(id: String) async throws -> CalendarEventRecord
}

struct CalendarReadTool: Tool {
    let definition = ToolDefinition(
        name: CalendarToolCatalog.readID,
        displayName: String(localized: "tools.calendar.read.name"),
        summary: String(localized: "tools.calendar.read.summary"),
        symbolName: "calendar",
        parameters: CalendarToolSchemas.readEvents
    )

    private let eventStore: any CalendarEventStore

    init(eventStore: any CalendarEventStore = SystemCalendarEventStore.shared) {
        self.eventStore = eventStore
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = CalendarToolArguments(call.arguments)
            let startDate = try arguments.requiredDate("start_date")
            let endDate = try arguments.requiredDate("end_date")
            guard endDate > startDate else {
                throw CalendarToolInputError.invalidDateRange
            }

            let criteria = CalendarReadCriteria(
                startDate: startDate,
                endDate: endDate,
                limit: try arguments.optionalInt("limit", defaultValue: 20, maximum: 100)
            )
            let events = try await eventStore.fetchEvents(criteria: criteria)
            return ToolResult(
                callID: call.id,
                content: try CalendarToolFormatter.encodedRead(events: events)
            )
        } catch let error as CalendarToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch let error as CalendarToolAuthorizationError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct CalendarCreateTool: Tool {
    let definition = ToolDefinition(
        name: CalendarToolCatalog.createID,
        displayName: String(localized: "tools.calendar.create.name"),
        summary: String(localized: "tools.calendar.create.summary"),
        symbolName: "calendar.badge.plus",
        parameters: CalendarToolSchemas.createEvent
    )

    private let eventStore: any CalendarEventStore

    init(eventStore: any CalendarEventStore = SystemCalendarEventStore.shared) {
        self.eventStore = eventStore
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = CalendarToolArguments(call.arguments)
            let title = try arguments.requiredTrimmedString("title")
            let startDate = try arguments.requiredDate("start_date")
            let isAllDay = try arguments.optionalBool("is_all_day", defaultValue: false)
            let endDate = try resolvedEndDate(
                arguments: arguments,
                startDate: startDate,
                isAllDay: isAllDay
            )
            guard endDate > startDate else {
                throw CalendarToolInputError.invalidDateRange
            }

            let draft = CalendarEventDraft(
                title: title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                notes: try arguments.optionalTrimmedString("notes"),
                location: try arguments.optionalTrimmedString("location"),
                url: try arguments.optionalURL("url")
            )
            let event = try await eventStore.saveEvent(draft: draft)
            return ToolResult(
                callID: call.id,
                content: try CalendarToolFormatter.encodedMutation(status: "created", event: event)
            )
        } catch let error as CalendarToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch let error as CalendarToolAuthorizationError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch let error as CalendarToolStoreError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }

    private func resolvedEndDate(
        arguments: CalendarToolArguments,
        startDate: Date,
        isAllDay: Bool
    ) throws -> Date {
        if let endDate = try arguments.optionalDate("end_date") {
            return endDate
        }

        let component: Calendar.Component = isAllDay ? .day : .minute
        let value = isAllDay
            ? 1
            : try arguments.optionalInt("duration_minutes", defaultValue: 60, maximum: 10_080)
        guard let endDate = Calendar.current.date(byAdding: component, value: value, to: startDate) else {
            throw CalendarToolInputError.invalidDateRange
        }

        return endDate
    }
}

struct CalendarUpdateTool: Tool {
    let definition = ToolDefinition(
        name: CalendarToolCatalog.updateID,
        displayName: String(localized: "tools.calendar.update.name"),
        summary: String(localized: "tools.calendar.update.summary"),
        symbolName: "calendar.badge.clock",
        parameters: CalendarToolSchemas.updateEvent
    )

    private let eventStore: any CalendarEventStore

    init(eventStore: any CalendarEventStore = SystemCalendarEventStore.shared) {
        self.eventStore = eventStore
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = CalendarToolArguments(call.arguments)
            let update = CalendarEventUpdate(
                id: try arguments.requiredTrimmedString("id"),
                title: try arguments.optionalNonEmptyTrimmedString("title"),
                startDate: try arguments.optionalDate("start_date"),
                endDate: try arguments.optionalDate("end_date"),
                isAllDay: try arguments.optionalBool("is_all_day"),
                notes: try arguments.optionalTrimmedString("notes"),
                location: try arguments.optionalTrimmedString("location"),
                url: try arguments.optionalURL("url"),
                clearsNotes: try arguments.optionalBool("clear_notes", defaultValue: false),
                clearsLocation: try arguments.optionalBool("clear_location", defaultValue: false),
                clearsURL: try arguments.optionalBool("clear_url", defaultValue: false)
            )
            guard update.hasChanges else {
                throw CalendarToolInputError.noUpdateFields
            }
            if let startDate = update.startDate,
               let endDate = update.endDate,
               endDate <= startDate {
                throw CalendarToolInputError.invalidDateRange
            }

            let event = try await eventStore.updateEvent(update: update)
            return ToolResult(
                callID: call.id,
                content: try CalendarToolFormatter.encodedMutation(status: "updated", event: event)
            )
        } catch let error as CalendarToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch let error as CalendarToolAuthorizationError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch let error as CalendarToolStoreError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

struct CalendarDeleteTool: Tool {
    let definition = ToolDefinition(
        name: CalendarToolCatalog.deleteID,
        displayName: String(localized: "tools.calendar.delete.name"),
        summary: String(localized: "tools.calendar.delete.summary"),
        symbolName: "calendar.badge.minus",
        parameters: CalendarToolSchemas.deleteEvent
    )

    private let eventStore: any CalendarEventStore

    init(eventStore: any CalendarEventStore = SystemCalendarEventStore.shared) {
        self.eventStore = eventStore
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        do {
            let arguments = CalendarToolArguments(call.arguments)
            let id = try arguments.requiredTrimmedString("id")
            let event = try await eventStore.deleteEvent(id: id)
            return ToolResult(
                callID: call.id,
                content: try CalendarToolFormatter.encodedMutation(status: "deleted", event: event)
            )
        } catch let error as CalendarToolInputError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch let error as CalendarToolAuthorizationError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        } catch let error as CalendarToolStoreError {
            return ToolResult(callID: call.id, content: error.localizedDescription, status: .error)
        }
    }
}

private final class SystemCalendarEventStore: CalendarEventStore {
    static let shared = SystemCalendarEventStore()

    private let eventStore = EKEventStore()

    @MainActor
    func fetchEvents(criteria: CalendarReadCriteria) async throws -> [CalendarEventRecord] {
        try await ensureFullAccess()
        let predicate = eventStore.predicateForEvents(
            withStart: criteria.startDate,
            end: criteria.endDate,
            calendars: nil
        )
        return eventStore.events(matching: predicate)
            .sorted {
                if $0.startDate == $1.startDate {
                    let lhsTitle = $0.title ?? ""
                    let rhsTitle = $1.title ?? ""
                    return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
                }

                return $0.startDate < $1.startDate
            }
            .prefix(criteria.limit)
            .map(CalendarEventRecord.init(event:))
    }

    @MainActor
    func saveEvent(draft: CalendarEventDraft) async throws -> CalendarEventRecord {
        try await ensureWriteAccess()
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarToolAuthorizationError.writeAccessDenied
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.notes = draft.notes
        event.location = draft.location
        event.url = draft.url

        try eventStore.save(event, span: .thisEvent, commit: true)
        return CalendarEventRecord(event: event)
    }

    @MainActor
    func updateEvent(update: CalendarEventUpdate) async throws -> CalendarEventRecord {
        try await ensureFullAccess()
        guard let event = eventStore.event(withIdentifier: update.id) else {
            throw CalendarToolStoreError.missingEvent(update.id)
        }

        if let title = update.title {
            event.title = title
        }

        guard let currentStartDate = event.startDate,
              let currentEndDate = event.endDate else {
            throw CalendarToolStoreError.missingEvent(update.id)
        }

        let originalDuration = currentEndDate.timeIntervalSince(currentStartDate)
        let nextStartDate = update.startDate ?? currentStartDate
        let nextEndDate: Date
        if let endDate = update.endDate {
            nextEndDate = endDate
        } else if update.startDate != nil,
                  update.isAllDay == true,
                  let allDayEndDate = Calendar.current.date(byAdding: .day, value: 1, to: nextStartDate) {
            nextEndDate = allDayEndDate
        } else if update.startDate != nil {
            nextEndDate = nextStartDate.addingTimeInterval(originalDuration)
        } else {
            nextEndDate = currentEndDate
        }
        guard nextEndDate > nextStartDate else {
            throw CalendarToolInputError.invalidDateRange
        }

        event.startDate = nextStartDate
        event.endDate = nextEndDate
        if let isAllDay = update.isAllDay {
            event.isAllDay = isAllDay
        }

        if update.clearsNotes {
            event.notes = nil
        } else if let notes = update.notes {
            event.notes = notes
        }
        if update.clearsLocation {
            event.location = nil
        } else if let location = update.location {
            event.location = location
        }
        if update.clearsURL {
            event.url = nil
        } else if let url = update.url {
            event.url = url
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        return CalendarEventRecord(event: event)
    }

    @MainActor
    func deleteEvent(id: String) async throws -> CalendarEventRecord {
        try await ensureFullAccess()
        guard let event = eventStore.event(withIdentifier: id) else {
            throw CalendarToolStoreError.missingEvent(id)
        }

        let record = CalendarEventRecord(event: event)
        try eventStore.remove(event, span: .thisEvent, commit: true)
        return record
    }

    @MainActor
    private func ensureFullAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined, .writeOnly:
            guard try await requestFullAccess(),
                  EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                throw CalendarToolAuthorizationError.fullAccessDenied
            }
        case .denied:
            throw CalendarToolAuthorizationError.fullAccessDenied
        case .restricted:
            throw CalendarToolAuthorizationError.restricted
        @unknown default:
            throw CalendarToolAuthorizationError.fullAccessDenied
        }
    }

    @MainActor
    private func ensureWriteAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return
        case .notDetermined:
            let didGrantAccess = try await requestWriteOnlyAccess()
            let authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            guard didGrantAccess || authorizationStatus == .writeOnly || authorizationStatus == .fullAccess else {
                throw CalendarToolAuthorizationError.writeAccessDenied
            }
        case .denied:
            throw CalendarToolAuthorizationError.writeAccessDenied
        case .restricted:
            throw CalendarToolAuthorizationError.restricted
        @unknown default:
            throw CalendarToolAuthorizationError.writeAccessDenied
        }
    }

    @MainActor
    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    @MainActor
    private func requestWriteOnlyAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestWriteOnlyAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

private extension CalendarEventRecord {
    init(event: EKEvent) {
        id = event.eventIdentifier
        title = event.title ?? ""
        calendarTitle = event.calendar?.title
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        notes = event.notes
        location = event.location
        url = event.url
    }
}

private enum CalendarToolSchemas {
    static let createEvent = objectSchema(
        properties: [
            "title": stringSchema(description: "Event title."),
            "start_date": stringSchema(description: "ISO 8601 event start date or date-time."),
            "end_date": stringSchema(
                description: "Optional ISO 8601 event end date or date-time. Must be after start_date."
            ),
            "duration_minutes": integerSchema(
                description: "Event duration in minutes when end_date is omitted. Defaults to 60.",
                maximum: 10_080
            ),
            "is_all_day": boolSchema(
                description: "Whether to create an all-day event. Defaults to false."
            ),
            "location": stringSchema(description: "Optional event location."),
            "notes": stringSchema(description: "Optional event notes."),
            "url": stringSchema(description: "Optional event URL.")
        ],
        required: ["title", "start_date"]
    )

    static let readEvents = objectSchema(
        properties: [
            "start_date": stringSchema(
                description: "ISO 8601 start date or date-time for the event search range."
            ),
            "end_date": stringSchema(
                description: "ISO 8601 end date or date-time for the event search range. Must be after start_date."
            ),
            "limit": integerSchema(
                description: "Maximum number of events to return. Defaults to 20.",
                maximum: 100
            )
        ],
        required: ["start_date", "end_date"]
    )

    static let updateEvent = objectSchema(
        properties: [
            "id": stringSchema(description: "Event ID returned by a calendar tool."),
            "title": stringSchema(description: "Event title."),
            "start_date": stringSchema(description: "ISO 8601 event start date or date-time."),
            "end_date": stringSchema(
                description: "Optional ISO 8601 event end date or date-time. Must be after start_date."
            ),
            "is_all_day": boolSchema(
                description: "Whether the event is all-day."
            ),
            "location": stringSchema(description: "Optional event location."),
            "notes": stringSchema(description: "Optional event notes."),
            "url": stringSchema(description: "Optional event URL."),
            "clear_location": boolSchema(description: "Clear the existing event location."),
            "clear_notes": boolSchema(description: "Clear the existing event notes."),
            "clear_url": boolSchema(description: "Clear the existing event URL.")
        ],
        required: ["id"]
    )

    static let deleteEvent = objectSchema(
        properties: [
            "id": stringSchema(description: "Event ID returned by a calendar tool.")
        ],
        required: ["id"]
    )

    private static func objectSchema(
        properties: [String: JSONValue],
        required: [String]
    ) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
            "additionalProperties": .bool(false)
        ])
    }

    private static func stringSchema(description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private static func integerSchema(description: String, maximum: Int) -> JSONValue {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(1),
            "maximum": .int(maximum)
        ])
    }

    private static func boolSchema(description: String) -> JSONValue {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }
}

private struct CalendarToolArguments {
    private let arguments: [String: JSONValue]

    init(_ arguments: [String: JSONValue]) {
        self.arguments = arguments
    }

    func requiredTrimmedString(_ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue else {
            throw CalendarToolInputError.missingArgument(key)
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw CalendarToolInputError.emptyArgument(key)
        }

        return trimmedValue
    }

    func optionalTrimmedString(_ key: String) throws -> String? {
        guard let value = arguments[key] else {
            return nil
        }
        guard let stringValue = value.stringValue else {
            throw CalendarToolInputError.emptyArgument(key)
        }

        let trimmedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    func optionalNonEmptyTrimmedString(_ key: String) throws -> String? {
        guard let value = arguments[key] else {
            return nil
        }
        guard let stringValue = value.stringValue else {
            throw CalendarToolInputError.emptyArgument(key)
        }

        let trimmedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw CalendarToolInputError.emptyArgument(key)
        }

        return trimmedValue
    }

    func requiredDate(_ key: String) throws -> Date {
        try CalendarToolDateParser.date(from: requiredTrimmedString(key), key: key)
    }

    func optionalDate(_ key: String) throws -> Date? {
        guard let value = try optionalTrimmedString(key) else {
            return nil
        }

        return try CalendarToolDateParser.date(from: value, key: key)
    }

    func optionalURL(_ key: String) throws -> URL? {
        guard let value = try optionalTrimmedString(key) else {
            return nil
        }
        guard let url = URL(string: value),
              url.scheme != nil,
              url.host != nil else {
            throw CalendarToolInputError.invalidURL(key)
        }

        return url
    }

    func optionalBool(_ key: String, defaultValue: Bool) throws -> Bool {
        guard let value = arguments[key] else {
            return defaultValue
        }

        return try boolValue(value, key: key)
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = arguments[key] else {
            return nil
        }

        return try boolValue(value, key: key)
    }

    private func boolValue(_ value: JSONValue, key: String) throws -> Bool {
        switch value {
        case let .bool(boolValue):
            return boolValue
        case let .string(stringValue):
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                throw CalendarToolInputError.invalidBool(key)
            }
        default:
            throw CalendarToolInputError.invalidBool(key)
        }
    }

    func optionalInt(_ key: String, defaultValue: Int, maximum: Int) throws -> Int {
        guard let value = arguments[key] else {
            return defaultValue
        }

        let intValue: Int
        switch value {
        case let .int(value):
            intValue = value
        case let .double(value):
            guard value.rounded() == value else {
                throw CalendarToolInputError.invalidInteger(key, maximum: maximum)
            }
            intValue = Int(value)
        case let .string(value):
            guard let parsedValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw CalendarToolInputError.invalidInteger(key, maximum: maximum)
            }
            intValue = parsedValue
        default:
            throw CalendarToolInputError.invalidInteger(key, maximum: maximum)
        }

        guard (1...maximum).contains(intValue) else {
            throw CalendarToolInputError.invalidInteger(key, maximum: maximum)
        }

        return intValue
    }
}

private enum CalendarToolDateParser {
    static func date(from value: String, key: String) throws -> Date {
        if let date = internetDateTimeFormatter(options: [.withInternetDateTime, .withFractionalSeconds])
            .date(from: value) {
            return date
        }
        if let date = internetDateTimeFormatter(options: [.withInternetDateTime]).date(from: value) {
            return date
        }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            if let date = localFormatter(format: format).date(from: value) {
                return date
            }
        }

        throw CalendarToolInputError.invalidDate(key)
    }

    private static func internetDateTimeFormatter(options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        return formatter
    }

    private static func localFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}

private enum CalendarToolInputError: LocalizedError {
    case missingArgument(String)
    case emptyArgument(String)
    case invalidBool(String)
    case invalidDate(String)
    case invalidDateRange
    case invalidInteger(String, maximum: Int)
    case invalidURL(String)
    case noUpdateFields

    var errorDescription: String? {
        switch self {
        case let .missingArgument(key):
            return Self.localized("tools.calendar.error.missing_argument_format", key)
        case let .emptyArgument(key):
            return Self.localized("tools.calendar.error.empty_argument_format", key)
        case let .invalidBool(key):
            return Self.localized("tools.calendar.error.invalid_bool_format", key)
        case let .invalidDate(key):
            return Self.localized("tools.calendar.error.invalid_date_format", key)
        case .invalidDateRange:
            return NSLocalizedString("tools.calendar.error.invalid_date_range", comment: "")
        case let .invalidInteger(key, maximum):
            return Self.localized("tools.calendar.error.invalid_integer_format", key, maximum)
        case let .invalidURL(key):
            return Self.localized("tools.calendar.error.invalid_url_format", key)
        case .noUpdateFields:
            return NSLocalizedString("tools.calendar.error.no_update_fields", comment: "")
        }
    }

    private static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: NSLocalizedString(key, comment: ""),
            locale: Locale.current,
            arguments: arguments
        )
    }
}

private enum CalendarToolAuthorizationError: LocalizedError {
    case fullAccessDenied
    case restricted
    case writeAccessDenied

    var errorDescription: String? {
        switch self {
        case .fullAccessDenied:
            return NSLocalizedString("tools.calendar.error.full_access_denied", comment: "")
        case .restricted:
            return NSLocalizedString("tools.calendar.error.access_restricted", comment: "")
        case .writeAccessDenied:
            return NSLocalizedString("tools.calendar.error.write_access_denied", comment: "")
        }
    }
}

private enum CalendarToolStoreError: LocalizedError {
    case missingEvent(String)

    var errorDescription: String? {
        switch self {
        case let .missingEvent(id):
            return String(
                format: NSLocalizedString("tools.calendar.error.missing_event_format", comment: ""),
                locale: Locale.current,
                id
            )
        }
    }
}

nonisolated private enum CalendarToolFormatter {
    nonisolated private struct EventPayload: Encodable {
        var id: String?
        var title: String
        var calendar: String?
        var startDate: String
        var endDate: String
        var isAllDay: Bool
        var notes: String?
        var location: String?
        var url: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case calendar
            case startDate = "start_date"
            case endDate = "end_date"
            case isAllDay = "is_all_day"
            case notes
            case location
            case url
        }

        nonisolated init(event: CalendarEventRecord) {
            id = event.id
            title = event.title
            calendar = event.calendarTitle
            startDate = CalendarToolFormatter.string(from: event.startDate)
            endDate = CalendarToolFormatter.string(from: event.endDate)
            isAllDay = event.isAllDay
            notes = event.notes
            location = event.location
            url = event.url?.absoluteString
        }
    }

    nonisolated private struct ReadPayload: Encodable {
        var count: Int
        var events: [EventPayload]
    }

    nonisolated private struct MutationPayload: Encodable {
        var status: String
        var event: EventPayload
    }

    nonisolated static func encodedRead(events: [CalendarEventRecord]) throws -> String {
        try encoded(
            ReadPayload(
                count: events.count,
                events: events.map(EventPayload.init(event:))
            )
        )
    }

    nonisolated static func encodedMutation(status: String, event: CalendarEventRecord) throws -> String {
        try encoded(
            MutationPayload(
                status: status,
                event: EventPayload(event: event)
            )
        )
    }

    nonisolated private static func encoded<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter.string(from: date)
    }
}
