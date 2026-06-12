//
//  ToolApprovalTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class ToolApprovalTests: UserDefaultsBackedTestCase {
    func testSensitiveToolRejectionPreventsExecution() async throws {
        let tool = ApprovalTestTool(name: CalendarToolCatalog.createID)
        let presenter = ApprovalPresenterSpy(decisions: [false])
        let toolManager = makeToolManager(tool: tool, presenter: presenter, storageKey: "approvalRejected")

        let result = try await toolManager.execute(
            call: ToolCall(
                id: "call_1",
                toolID: CalendarToolCatalog.createID,
                arguments: [
                    "title": .string("Planning"),
                    "start_date": .string("2026-06-10T09:00:00Z"),
                    "duration_minutes": .int(30)
                ]
            ),
            context: ToolExecutionContext()
        )

        XCTAssertEqual(result.status, .error)
        XCTAssertEqual(result.content, String(localized: "tools.approval.rejected"))
        XCTAssertEqual(tool.executionCount, 0)
        XCTAssertEqual(presenter.requests.map(\.toolID), [CalendarToolCatalog.createID])
        XCTAssertEqual(presenter.requests.first?.toolID, CalendarToolCatalog.createID)
        XCTAssertEqual(presenter.requests.first?.toolName, CalendarToolCatalog.createID)
        XCTAssertEqual(presenter.requests.first?.confirmationTitle, String(localized: "tools.approval.allow"))
    }

    func testSensitiveToolApprovalAllowsExecution() async throws {
        let tool = ApprovalTestTool(name: MemoryToolCatalog.addID)
        let presenter = ApprovalPresenterSpy(decisions: [true])
        let toolManager = makeToolManager(tool: tool, presenter: presenter, storageKey: "approvalAllowed")

        let result = try await toolManager.execute(
            call: ToolCall(
                id: "call_1",
                toolID: MemoryToolCatalog.addID,
                arguments: ["text": .string("User prefers concise answers.")]
            ),
            context: ToolExecutionContext()
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.content, "executed")
        XCTAssertEqual(tool.executionCount, 1)
        XCTAssertEqual(presenter.requests.map(\.toolID), [MemoryToolCatalog.addID])
        XCTAssertEqual(presenter.requests.first?.confirmationTitle, String(localized: "tools.approval.allow"))
    }

    func testSkippedToolDoesNotPresentApproval() async throws {
        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: "approvalSkipped",
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )
        settingsStore.saveApprovalSkipped(true, forToolID: MemoryToolCatalog.deleteID)

        let tool = ApprovalTestTool(name: MemoryToolCatalog.deleteID)
        let presenter = ApprovalPresenterSpy(decisions: [false])
        let toolManager = makeToolManager(
            tool: tool,
            presenter: presenter,
            settingsStore: settingsStore
        )

        let result = try await toolManager.execute(
            call: ToolCall(
                id: "call_1",
                toolID: MemoryToolCatalog.deleteID,
                arguments: ["id": .string(UUID().uuidString)]
            ),
            context: ToolExecutionContext()
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.content, "executed")
        XCTAssertEqual(tool.executionCount, 1)
        XCTAssertTrue(presenter.requests.isEmpty)
    }

    func testCancellingPendingApprovalPreventsExecution() async throws {
        let tool = ApprovalTestTool(name: CalendarToolCatalog.createID)
        let presenter = SuspendingApprovalPresenter()
        let toolManager = makeToolManager(
            tool: tool,
            presenter: presenter,
            storageKey: "approvalCancelled"
        )
        let task = Task {
            try await toolManager.execute(
                call: ToolCall(
                    id: "call_1",
                    toolID: CalendarToolCatalog.createID,
                    arguments: [
                        "title": .string("Planning"),
                        "start_date": .string("2026-06-10T09:00:00Z")
                    ]
                ),
                context: ToolExecutionContext()
            )
        }

        await presenter.waitForRequest()
        task.cancel()
        presenter.resolve(true)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to stop tool execution.")
        } catch is CancellationError {
            XCTAssertEqual(tool.executionCount, 0)
            XCTAssertEqual(presenter.requests.map(\.toolID), [CalendarToolCatalog.createID])
        }
    }

    func testCalendarUpdateApprovalShowsOriginalAndChangedValues() async throws {
        let tool = ApprovalTestTool(name: CalendarToolCatalog.updateID)
        let event = CalendarEventRecord(
            id: "event-1",
            title: "Team Sync",
            calendarTitle: "Work",
            startDate: try Self.date("2026-06-10T09:00:00Z"),
            endDate: try Self.date("2026-06-10T10:00:00Z"),
            isAllDay: false,
            notes: "Old agenda",
            location: "Old Room",
            url: nil
        )
        let provider = CalendarToolApprovalRequestProvider(
            contextProvider: ApprovalContextProviderStub(eventsByID: ["event-1": event])
        )
        let call = ToolCall(
            id: "call_1",
            toolID: CalendarToolCatalog.updateID,
            arguments: [
                "id": .string("event-1"),
                "title": .string("Team Review"),
                "location": .string("New Room"),
                "clear_notes": .bool(true)
            ]
        )
        let pendingRequest = await provider.approvalRequest(for: call, definition: tool.definition)
        let request = try XCTUnwrap(pendingRequest)
        let details = await provider.details(for: call)

        XCTAssertEqual(request.toolID, CalendarToolCatalog.updateID)
        XCTAssertEqual(request.toolName, CalendarToolCatalog.updateID)
        XCTAssertEqual(details.first?.id, "tools.approval.detail.event_id")
        XCTAssertEqual(details.first?.value, "Team Sync")
        XCTAssertFalse(details.contains { $0.value == "event-1" })

        let titleDetail = try XCTUnwrap(
            details.first { $0.id == "tools.approval.detail.title" }
        )
        XCTAssertEqual(titleDetail.change?.originalValue, "Team Sync")
        XCTAssertEqual(titleDetail.change?.changedValue, "Team Review")

        let locationDetail = try XCTUnwrap(
            details.first { $0.id == "tools.approval.detail.location" }
        )
        XCTAssertEqual(locationDetail.change?.originalValue, "Old Room")
        XCTAssertEqual(locationDetail.change?.changedValue, "New Room")

        let notesDetail = try XCTUnwrap(
            details.first { $0.id == "tools.approval.detail.notes" }
        )
        XCTAssertEqual(notesDetail.change?.originalValue, "Old agenda")
        XCTAssertEqual(notesDetail.change?.changedValue, String(localized: "tools.approval.value.empty"))
        XCTAssertFalse(details.contains { $0.id == "tools.approval.detail.start_time" })
    }

    func testCalendarDeleteApprovalShowsEventDetailsInsteadOfOnlyTitle() async throws {
        let tool = ApprovalTestTool(name: CalendarToolCatalog.deleteID)
        let event = CalendarEventRecord(
            id: "event-2",
            title: "Cancel This",
            calendarTitle: "Work",
            startDate: try Self.date("2026-06-10T09:00:00Z"),
            endDate: try Self.date("2026-06-10T10:00:00Z"),
            isAllDay: false,
            notes: "Bring agenda",
            location: "Room 8",
            url: URL(string: "https://example.com/meeting")
        )
        let provider = CalendarToolApprovalRequestProvider(
            contextProvider: ApprovalContextProviderStub(eventsByID: ["event-2": event])
        )
        let call = ToolCall(
            id: "call_1",
            toolID: CalendarToolCatalog.deleteID,
            arguments: ["id": .string("event-2")]
        )
        let pendingRequest = await provider.approvalRequest(for: call, definition: tool.definition)
        let request = try XCTUnwrap(pendingRequest)
        let details = await provider.details(for: call)

        XCTAssertEqual(request.toolID, CalendarToolCatalog.deleteID)
        XCTAssertTrue(request.isDestructive)
        XCTAssertEqual(request.confirmationTitle, String(localized: "tools.approval.allow_destructive"))
        XCTAssertEqual(details.first?.id, "tools.approval.detail.event_id")
        XCTAssertEqual(details.first?.value, "Cancel This")
        XCTAssertFalse(details.contains { $0.value == "event-2" })

        let timeDetail = try XCTUnwrap(
            details.first { $0.id == "tools.approval.detail.time" }
        )
        XCTAssertTrue(timeDetail.value.contains(" - "))
        XCTAssertEqual(
            details.first { $0.id == "tools.approval.detail.all_day" }?.value,
            String(localized: "tools.approval.value.no")
        )
        XCTAssertEqual(details.first { $0.id == "tools.approval.detail.calendar" }?.value, "Work")
        XCTAssertEqual(details.first { $0.id == "tools.approval.detail.location" }?.value, "Room 8")
        XCTAssertEqual(details.first { $0.id == "tools.approval.detail.notes" }?.value, "Bring agenda")
        XCTAssertEqual(
            details.first { $0.id == "tools.approval.detail.url" }?.value,
            "https://example.com/meeting"
        )
    }

    private func makeToolManager(
        tool: ApprovalTestTool,
        presenter: any ToolApprovalPresenter,
        storageKey: String,
        contextProvider: any CalendarToolApprovalContextProviding = EmptyCalendarApprovalContextProvider()
    ) -> ToolManager {
        let settingsStore = UserDefaultsToolSettingsStore(
            defaults: defaults,
            storageKey: storageKey,
            legacyMCPStorageKey: "missingLegacyMCPSettings"
        )
        return makeToolManager(
            tool: tool,
            presenter: presenter,
            settingsStore: settingsStore,
            contextProvider: contextProvider
        )
    }

    private func makeToolManager(
        tool: ApprovalTestTool,
        presenter: any ToolApprovalPresenter,
        settingsStore: UserDefaultsToolSettingsStore,
        contextProvider: any CalendarToolApprovalContextProviding = EmptyCalendarApprovalContextProvider()
    ) -> ToolManager {
        let registry = ToolRegistry(tools: [tool])
        let catalog = ToolCatalog(
            registry: registry,
            isEnabled: { true },
            isRegisteredToolEnabled: { _ in true }
        )
        let approvalManager = ToolApprovalManager(
            settingsStore: settingsStore,
            presenter: presenter,
            requestRegistry: ToolApprovalRequestRegistry(
                providers: [
                    CalendarToolApprovalRequestProvider(contextProvider: contextProvider),
                    MemoryToolApprovalRequestProvider()
                ]
            )
        )
        return ToolManager(
            catalog: catalog,
            approvalManager: approvalManager
        )
    }

    private static func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }
}

nonisolated private struct EmptyCalendarApprovalContextProvider: CalendarToolApprovalContextProviding {
    func calendarEvent(id: String) async -> CalendarEventRecord? {
        nil
    }
}

nonisolated private struct ApprovalContextProviderStub: CalendarToolApprovalContextProviding {
    var eventsByID: [String: CalendarEventRecord]

    func calendarEvent(id: String) async -> CalendarEventRecord? {
        eventsByID[id]
    }
}

private final class ApprovalTestTool: Tool {
    let definition: ToolDefinition
    private(set) var executionCount = 0

    init(name: String) {
        definition = ToolDefinition(
            name: name,
            displayName: name,
            summary: "Test tool",
            symbolName: "wrench"
        )
    }

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        executionCount += 1
        return ToolResult(callID: call.id, content: "executed")
    }
}

@MainActor
private final class ApprovalPresenterSpy: ToolApprovalPresenter {
    private var decisions: [Bool]
    private(set) var requests: [ToolApprovalRequest] = []

    init(decisions: [Bool]) {
        self.decisions = decisions
    }

    func requestApproval(_ request: ToolApprovalRequest) async -> Bool {
        requests.append(request)
        guard !decisions.isEmpty else {
            return false
        }

        return decisions.removeFirst()
    }
}

@MainActor
private final class SuspendingApprovalPresenter: ToolApprovalPresenter {
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private(set) var requests: [ToolApprovalRequest] = []

    func requestApproval(_ request: ToolApprovalRequest) async -> Bool {
        requests.append(request)
        requestContinuation?.resume()
        requestContinuation = nil

        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    func waitForRequest() async {
        guard requests.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func resolve(_ isApproved: Bool) {
        approvalContinuation?.resume(returning: isApproved)
        approvalContinuation = nil
    }
}
