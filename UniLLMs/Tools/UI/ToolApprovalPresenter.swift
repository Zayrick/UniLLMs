//
//  ToolApprovalPresenter.swift
//  UniLLMs
//
//  Presents SwiftUI approval UI for sensitive tool calls.
//

import SwiftUI
import UIKit

@MainActor
final class SwiftUIToolApprovalPresenter: ToolApprovalPresenter {
    func requestApproval(_ request: ToolApprovalRequest) async throws -> ToolApprovalDecision {
        let cancellation = ToolApprovalCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard let presenter = Self.topViewController() else {
                    continuation.resume(returning: .rejected)
                    return
                }

                let coordinator = ToolApprovalModalCoordinator(continuation: continuation)
                cancellation.coordinator = coordinator
                let modalView = ToolApprovalModalView(
                    toolName: request.toolName,
                    confirmationTitle: request.confirmationTitle,
                    confirmationRole: request.isDestructive ? .destructive : nil,
                    details: request.details
                ) { decision in
                    coordinator.resolve(decision)
                }
                let hostingController = UIHostingController(rootView: modalView)
                hostingController.modalPresentationStyle = .pageSheet
                coordinator.hostingController = hostingController
                hostingController.presentationController?.delegate = coordinator
                if let sheetPresentationController = hostingController.sheetPresentationController {
                    sheetPresentationController.detents = [.medium(), .large()]
                    sheetPresentationController.prefersGrabberVisible = true
                }

                presenter.present(hostingController, animated: true)
            }
        } onCancel: {
            Task { @MainActor in
                cancellation.cancel()
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let activeWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        return topViewController(from: activeWindow?.rootViewController)
    }

    private static func topViewController(from viewController: UIViewController?) -> UIViewController? {
        if let navigationController = viewController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = viewController as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        if let splitViewController = viewController as? UISplitViewController,
           let lastViewController = splitViewController.viewControllers.last {
            return topViewController(from: lastViewController)
        }

        if let presentedViewController = viewController?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        return viewController
    }
}

@MainActor
private final class ToolApprovalCancellation {
    weak var coordinator: ToolApprovalModalCoordinator?

    func cancel() {
        coordinator?.cancel()
    }
}

@MainActor
private final class ToolApprovalModalCoordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    var hostingController: UIViewController?

    private var continuation: CheckedContinuation<ToolApprovalDecision, Error>?

    init(continuation: CheckedContinuation<ToolApprovalDecision, Error>) {
        self.continuation = continuation
    }

    func resolve(_ decision: ToolApprovalDecision) {
        finish(.success(decision), shouldDismiss: true, animated: true)
    }

    func cancel() {
        finish(.failure(CancellationError()), shouldDismiss: true, animated: false)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(.success(.rejected), shouldDismiss: false, animated: false)
    }

    private func finish(
        _ result: Result<ToolApprovalDecision, Error>,
        shouldDismiss: Bool,
        animated: Bool
    ) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        let controller = hostingController
        hostingController = nil

        if shouldDismiss,
           let controller {
            controller.dismiss(animated: animated) {
                Self.resume(continuation, with: result)
            }
        } else {
            Self.resume(continuation, with: result)
        }
    }

    private static func resume(
        _ continuation: CheckedContinuation<ToolApprovalDecision, Error>,
        with result: Result<ToolApprovalDecision, Error>
    ) {
        switch result {
        case let .success(decision):
            continuation.resume(returning: decision)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

private struct ToolApprovalModalView: View {
    let toolName: String
    let confirmationTitle: String
    let confirmationRole: ButtonRole?
    let details: [ToolApprovalDetail]
    let onDecision: (ToolApprovalDecision) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                approvalTitleRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemGroupedBackground))

                Divider()

                ToolApprovalDetailList(details: details)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(String(localized: "tools.approval.navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .generalCancel), role: .cancel) {
                        onDecision(.rejected)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle, role: confirmationRole) {
                        onDecision(.approved)
                    }
                }
            }
        }
    }

    private var approvalTitleRow: some View {
        Label {
            Text(
                String(
                    format: NSLocalizedString("tools.approval.title_format", comment: ""),
                    locale: Locale.current,
                    toolName
                )
            )
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(confirmationRole == nil ? Color.accentColor : Color.red)
        }
        .labelStyle(.titleAndIcon)
    }
}

struct ToolApprovalDetailList: View {
    let details: [ToolApprovalDetail]

    var body: some View {
        Form {
            if !details.isEmpty {
                Section(String(localized: "tools.approval.details_header")) {
                    ForEach(details) { detail in
                        ToolApprovalDetailRow(detail: detail)
                    }
                }
            }
        }
    }
}

private struct ToolApprovalDetailRow: View {
    let detail: ToolApprovalDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            switch detail.value {
            case let .change(change):
                ToolApprovalChangeComparison(change: change)
            case let .text(value):
                Text(value)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolApprovalChangeComparison: View {
    let change: ToolApprovalValueChange

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(alignment: .top, horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    valueBlock(title: beforeLabel, value: change.originalValue)
                        .frame(minWidth: 120, maxWidth: 220, alignment: .leading)

                    Image(systemName: "arrow.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 28)
                        .accessibilityHidden(true)

                    valueBlock(title: afterLabel, value: change.changedValue)
                        .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                valueBlock(title: beforeLabel, value: change.originalValue)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                valueBlock(title: afterLabel, value: change.changedValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var beforeLabel: String {
        String(localized: "tools.approval.value.before")
    }

    private var afterLabel: String {
        String(localized: "tools.approval.value.after")
    }

    private var accessibilityText: String {
        String(
            format: NSLocalizedString("tools.approval.value.changed_format", comment: ""),
            locale: Locale.current,
            change.originalValue,
            change.changedValue
        )
    }

    private func valueBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }
}

#Preview {
    ToolApprovalModalView(
        toolName: "Create Calendar Event",
        confirmationTitle: String(localized: "tools.approval.allow"),
        confirmationRole: nil,
        details: [
            ToolApprovalDetail(id: "title", label: "Title", value: .text("Design review")),
            ToolApprovalDetail(
                id: "time",
                label: "Time",
                value: .text("Jun 10, 2026, 9:00 AM - Jun 10, 2026, 10:00 AM")
            ),
            ToolApprovalDetail(
                id: "location",
                label: "Location",
                value: .change(
                    ToolApprovalValueChange(
                        originalValue: "Old Room",
                        changedValue: "New Room"
                    )
                )
            )
        ]
    ) { _ in }
}
