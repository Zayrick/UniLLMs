//
//  ToolApproval.swift
//  UniLLMs
//
//  Approval request routing for sensitive tools.
//

import Foundation

nonisolated struct ToolApprovalValueChange: Equatable {
    var originalValue: String
    var changedValue: String
}

nonisolated struct ToolApprovalDetail: Equatable, Identifiable {
    enum Value: Equatable {
        case text(String)
        case change(ToolApprovalValueChange)
    }

    var id: String
    var label: String
    var value: Value

    var text: String? {
        guard case let .text(text) = value else {
            return nil
        }

        return text
    }

    var change: ToolApprovalValueChange? {
        guard case let .change(change) = value else {
            return nil
        }

        return change
    }
}

struct ToolApprovalRequest {
    var toolID: String
    var toolName: String
    var confirmationTitle: String
    var isDestructive: Bool
    var details: [ToolApprovalDetail]
}

nonisolated enum ToolApprovalDecision: Equatable {
    case approved
    case rejected
}

protocol ToolApprovalPresenter: AnyObject {
    @MainActor func requestApproval(_ request: ToolApprovalRequest) async throws -> ToolApprovalDecision
}

protocol ToolApprovalRequestProviding {
    var toolIDs: Set<String> { get }

    func approvalRequest(
        for call: ToolCall,
        definition: ToolDefinition
    ) async -> ToolApprovalRequest?
}

final class ToolApprovalRequestRegistry {
    private let providersByToolID: [String: any ToolApprovalRequestProviding]

    init(providers: [any ToolApprovalRequestProviding]) {
        var providersByToolID: [String: any ToolApprovalRequestProviding] = [:]
        for provider in providers {
            for toolID in provider.toolIDs {
                providersByToolID[toolID] = provider
            }
        }
        self.providersByToolID = providersByToolID
    }

    func containsProvider(forToolID toolID: String) -> Bool {
        providersByToolID[toolID] != nil
    }

    func approvalRequest(
        for call: ToolCall,
        definition: ToolDefinition
    ) async -> ToolApprovalRequest? {
        await providersByToolID[call.toolID]?.approvalRequest(
            for: call,
            definition: definition
        )
    }
}

protocol ToolApprovalManaging {
    func requestApprovalIfNeeded(call: ToolCall, definition: ToolDefinition) async throws -> ToolApprovalDecision
}

final class ToolApprovalManager: ToolApprovalManaging {
    private let settingsStore: any ToolSettingsStore
    private let presenter: any ToolApprovalPresenter
    private let requestRegistry: ToolApprovalRequestRegistry

    init(
        settingsStore: any ToolSettingsStore,
        presenter: any ToolApprovalPresenter,
        requestRegistry: ToolApprovalRequestRegistry
    ) {
        self.settingsStore = settingsStore
        self.presenter = presenter
        self.requestRegistry = requestRegistry
    }

    func requestApprovalIfNeeded(call: ToolCall, definition: ToolDefinition) async throws -> ToolApprovalDecision {
        guard requestRegistry.containsProvider(forToolID: call.toolID) else {
            return .approved
        }

        if settingsStore.isApprovalSkipped(forToolID: call.toolID) {
            return .approved
        }

        guard let request = await requestRegistry.approvalRequest(
            for: call,
            definition: definition
        ) else {
            return .approved
        }

        return try await presenter.requestApproval(request)
    }
}

nonisolated enum ToolApprovalDetailBuilder {
    static func compact(_ details: [ToolApprovalDetail?]) -> [ToolApprovalDetail] {
        details.compactMap { $0 }
    }

    static func detail(_ labelKey: String, value: String?) -> ToolApprovalDetail? {
        guard let value = sanitized(value) else {
            return nil
        }

        return ToolApprovalDetail(
            id: labelKey,
            label: NSLocalizedString(labelKey, comment: ""),
            value: .text(value)
        )
    }

    static func changedDetail(
        _ labelKey: String,
        originalValue: String?,
        changedValue: String?
    ) -> ToolApprovalDetail? {
        guard let originalValue = sanitized(originalValue),
              let changedValue = sanitized(changedValue),
              originalValue != changedValue else {
            return nil
        }

        return ToolApprovalDetail(
            id: labelKey,
            label: NSLocalizedString(labelKey, comment: ""),
            value: .change(
                ToolApprovalValueChange(
                    originalValue: originalValue,
                    changedValue: changedValue
                )
            )
        )
    }

    static func appendChangedDetail(
        _ details: inout [ToolApprovalDetail],
        labelKey: String,
        originalValue: String?,
        changedValue: String?
    ) {
        if let detail = changedDetail(labelKey, originalValue: originalValue, changedValue: changedValue) {
            details.append(detail)
        }
    }

    static func sanitized(_ value: String?) -> String? {
        guard let trimmedValue = trimmed(value) else {
            return nil
        }

        if trimmedValue.count <= 240 {
            return trimmedValue
        }

        let endIndex = trimmedValue.index(trimmedValue.startIndex, offsetBy: 240)
        return String(trimmedValue[..<endIndex]) + "..."
    }

    static func trimmed(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    static func stringValue(_ value: JSONValue?) -> String? {
        guard case let .string(stringValue) = value else {
            return nil
        }

        return stringValue
    }

    static func integerText(_ value: JSONValue?) -> String? {
        guard let intValue = integerValue(value) else {
            return nil
        }

        return String(intValue)
    }

    static func integerValue(_ value: JSONValue?) -> Int? {
        switch value {
        case let .int(intValue):
            return intValue
        case let .double(doubleValue) where doubleValue.rounded() == doubleValue:
            return Int(doubleValue)
        case let .string(stringValue):
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    static func boolValue(_ value: JSONValue?) -> Bool? {
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
                return nil
            }
        default:
            return nil
        }
    }

    static func boolText(_ value: Bool) -> String {
        value
            ? NSLocalizedString("tools.approval.value.yes", comment: "")
            : NSLocalizedString("tools.approval.value.no", comment: "")
    }

    static var emptyText: String {
        NSLocalizedString("tools.approval.value.empty", comment: "")
    }
}
