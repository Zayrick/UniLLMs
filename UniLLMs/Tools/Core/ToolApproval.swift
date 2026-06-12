//
//  ToolApproval.swift
//  UniLLMs
//
//  Approval request routing for sensitive tools.
//

import Foundation
import SwiftUI

nonisolated struct ToolApprovalValueChange: Equatable {
    var originalValue: String
    var changedValue: String
}

nonisolated struct ToolApprovalDetail: Equatable, Identifiable {
    var id: String
    var label: String
    var value: String
    var change: ToolApprovalValueChange?
}

struct ToolApprovalRequest {
    var toolID: String
    var toolName: String
    var confirmationTitle: String
    var isDestructive: Bool

    private let contentBuilder: @MainActor () -> AnyView

    init<Content: View>(
        toolID: String,
        toolName: String,
        confirmationTitle: String,
        isDestructive: Bool = false,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.toolID = toolID
        self.toolName = toolName
        self.confirmationTitle = confirmationTitle
        self.isDestructive = isDestructive
        contentBuilder = {
            AnyView(content())
        }
    }

    @MainActor
    func makeContent() -> AnyView {
        contentBuilder()
    }
}

nonisolated enum ToolApprovalDecision: Equatable {
    case approved
    case rejected(String)
}

protocol ToolApprovalPresenter: AnyObject {
    @MainActor func requestApproval(_ request: ToolApprovalRequest) async -> Bool
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
    func requestApprovalIfNeeded(call: ToolCall, definition: ToolDefinition) async -> ToolApprovalDecision
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

    func requestApprovalIfNeeded(call: ToolCall, definition: ToolDefinition) async -> ToolApprovalDecision {
        if settingsStore.isApprovalSkipped(forToolID: call.toolID) {
            return .approved
        }

        guard let request = await requestRegistry.approvalRequest(
            for: call,
            definition: definition
        ) else {
            return .approved
        }

        let isApproved = await presenter.requestApproval(request)
        return isApproved
            ? .approved
            : .rejected(String(localized: "tools.approval.rejected"))
    }
}
