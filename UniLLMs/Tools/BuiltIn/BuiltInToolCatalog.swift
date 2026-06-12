//
//  BuiltInToolCatalog.swift
//  UniLLMs
//
//  Owns concrete built-in tool registration.
//  Created by Zayrick on 2026/5/16.
//

import Foundation

nonisolated struct BuiltInToolPresentationOverride: Equatable {
    var title: String?
    var symbolName: String?
}

nonisolated struct BuiltInToolGroupDescriptor: Equatable, Identifiable {
    var id: String
    var toolIDs: [String]
    var title: String
    var sectionTitle: String
    var listTitle: String
    var detailText: String
    var symbolName: String
    var listSymbolName: String
    var approvalSkipDetail: String
    var presentationOverridesByToolID: [String: BuiltInToolPresentationOverride]

    func presentationOverride(forToolID toolID: String) -> BuiltInToolPresentationOverride? {
        presentationOverridesByToolID[toolID]
    }
}

enum BuiltInToolCatalog {
    static func makeRegistry(memoryManager: MemoryManager) -> ToolRegistry {
        ToolRegistry(
            tools: [
                DateTimeTool(),
                CalendarCreateTool(),
                CalendarReadTool(),
                CalendarUpdateTool(),
                CalendarDeleteTool(),
                MemoryAddTool(memoryManager: memoryManager),
                MemoryDeleteTool(memoryManager: memoryManager),
                MemoryListTool(memoryManager: memoryManager),
                MemorySearchTool(memoryManager: memoryManager),
                MemoryUpdateTool(memoryManager: memoryManager)
            ]
        )
    }

    static func makeApprovalRequestProviders(
        calendarContextProvider: any CalendarToolApprovalContextProviding = SystemCalendarToolApprovalContextProvider()
    ) -> [any ToolApprovalRequestProviding] {
        [
            CalendarToolApprovalRequestProvider(contextProvider: calendarContextProvider),
            MemoryToolApprovalRequestProvider()
        ]
    }

    static var approvalSkippableToolIDs: Set<String> {
        Set(makeApprovalRequestProviders().flatMap(\.toolIDs))
    }

    static var toolGroups: [BuiltInToolGroupDescriptor] {
        [
            BuiltInToolGroupDescriptor(
                id: "calendar",
                toolIDs: CalendarToolCatalog.toolIDs,
                title: String(localized: "tools.calendar_tools"),
                sectionTitle: String(localized: "tools.section.calendar"),
                listTitle: String(localized: "tools.calendar_tools.list"),
                detailText: String(localized: "tools.calendar_tools.detail"),
                symbolName: "calendar",
                listSymbolName: "calendar.badge.clock",
                approvalSkipDetail: String(localized: "tools.approval.calendar_skip_detail"),
                presentationOverridesByToolID: [:]
            ),
            BuiltInToolGroupDescriptor(
                id: "memory",
                toolIDs: MemoryToolCatalog.toolIDs,
                title: String(localized: "tools.memory_tools"),
                sectionTitle: String(localized: .toolsSectionMemory),
                listTitle: String(localized: "tools.memory_tools.list"),
                detailText: String(localized: "tools.memory_tools.detail"),
                symbolName: "brain.head.profile",
                listSymbolName: "brain.head.profile",
                approvalSkipDetail: String(localized: "tools.approval.memory_skip_detail"),
                presentationOverridesByToolID: Dictionary(
                    uniqueKeysWithValues: MemoryToolCatalog.userFacingItems.map {
                        (
                            $0.id,
                            BuiltInToolPresentationOverride(
                                title: $0.title,
                                symbolName: $0.symbolName
                            )
                        )
                    }
                )
            )
        ]
    }
}
