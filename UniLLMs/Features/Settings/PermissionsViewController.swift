//
//  PermissionsViewController.swift
//  UniLLMs
//
//  Hosts app permission status and permission-related shortcuts.
//

import AVFoundation
import Combine
import EventKit
import SwiftUI
import UIKit

final class PermissionsViewController: UIHostingController<PermissionsForm> {
    private let model: PermissionsModel

    init() {
        let model = PermissionsModel()
        self.model = model
        super.init(rootView: PermissionsForm(model: model))
    }

    @MainActor
    required init?(coder: NSCoder) {
        let model = PermissionsModel()
        self.model = model
        super.init(coder: coder, rootView: PermissionsForm(model: model))
    }
}

struct PermissionsForm: View {
    @Environment(\.openURL) private var openURL

    private let model: PermissionsModel

    fileprivate init(model: PermissionsModel) {
        self.model = model
    }

    var body: some View {
        Form {
            mediaSection
            calendarSection
            shortcutsSection
        }
        .navigationTitle(String(localized: "permissions.title"))
        .onAppear(perform: model.refreshStates)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.refreshStates()
        }
    }

    private var mediaSection: some View {
        Section(String(localized: "permissions.section.media")) {
            PermissionStatusRow(
                title: String(localized: "permissions.camera.title"),
                detail: String(localized: "permissions.camera.detail"),
                symbolName: "camera",
                iconTintColor: .systemBlue,
                state: model.cameraState,
                action: model.requestCameraIfNeeded
            )

            PermissionStatusRow(
                title: String(localized: "permissions.photos_picker.title"),
                detail: String(localized: "permissions.photos_picker.detail"),
                symbolName: "photo.on.rectangle.angled",
                iconTintColor: .systemPink,
                state: .notRequired,
                action: nil
            )
        }
    }

    private var calendarSection: some View {
        Section(String(localized: "permissions.section.calendar")) {
            PermissionStatusRow(
                title: String(localized: "permissions.calendar.title"),
                detail: String(localized: "permissions.calendar.detail"),
                symbolName: "calendar",
                iconTintColor: .systemOrange,
                state: model.calendarState,
                action: model.requestCalendarFullAccessIfNeeded
            )
        }
    }

    private var shortcutsSection: some View {
        Section(String(localized: "permissions.section.shortcuts")) {
            Button {
                openAppSettings()
            } label: {
                HStack(spacing: 12.0) {
                    SettingsRowLabel(
                        title: String(localized: "permissions.open_settings.title"),
                        subtitle: String(localized: "permissions.open_settings.detail"),
                        symbolName: "gearshape",
                        tintColor: .systemGray
                    )
                    Spacer(minLength: 8.0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        openURL(url)
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let detail: String
    let symbolName: String
    let iconTintColor: UIColor
    let state: PermissionState
    let action: (() -> Void)?

    var body: some View {
        Group {
            if state.action == .none {
                content
            } else {
                Button {
                    action?()
                } label: {
                    content
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail), \(state.title)")
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12.0) {
            SettingsRowLabel(
                title: title,
                subtitle: detail,
                symbolName: symbolName,
                tintColor: state.dimsIcon ? .tertiaryLabel : iconTintColor
            )

            Spacer(minLength: 8.0)

            Text(state.title)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: state.tintColor))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
    }
}

private enum PermissionAction {
    case none
    case requestCamera
    case requestCalendarFullAccess
}

private struct PermissionState {
    let title: String
    let tintColor: UIColor
    let action: PermissionAction
    let dimsIcon: Bool

    static let authorized = PermissionState(
        title: String(localized: "permissions.status.authorized"),
        tintColor: .systemGreen,
        action: .none,
        dimsIcon: false
    )

    static let denied = PermissionState(
        title: String(localized: "permissions.status.denied"),
        tintColor: .systemRed,
        action: .none,
        dimsIcon: true
    )

    static let restricted = PermissionState(
        title: String(localized: "permissions.status.restricted"),
        tintColor: .systemRed,
        action: .none,
        dimsIcon: true
    )

    static let notRequired = PermissionState(
        title: String(localized: "permissions.status.not_required"),
        tintColor: .secondaryLabel,
        action: .none,
        dimsIcon: false
    )

    static let unavailable = PermissionState(
        title: String(localized: "permissions.status.unavailable"),
        tintColor: .systemRed,
        action: .none,
        dimsIcon: true
    )

    static let unknown = PermissionState(
        title: String(localized: "permissions.status.unknown"),
        tintColor: .secondaryLabel,
        action: .none,
        dimsIcon: true
    )

    static func notDetermined(action: PermissionAction) -> PermissionState {
        PermissionState(
            title: String(localized: "permissions.status.not_determined"),
            tintColor: .secondaryLabel,
            action: action,
            dimsIcon: false
        )
    }

    static func calendarFullAccess(action: PermissionAction = .none) -> PermissionState {
        PermissionState(
            title: String(localized: "permissions.status.full_access"),
            tintColor: .systemGreen,
            action: action,
            dimsIcon: false
        )
    }

    static func calendarWriteOnly(action: PermissionAction = .none) -> PermissionState {
        PermissionState(
            title: String(localized: "permissions.status.write_only"),
            tintColor: .systemOrange,
            action: action,
            dimsIcon: false
        )
    }
}

@MainActor
@Observable
private final class PermissionsModel {
    @ObservationIgnored private let calendarEventStore = EKEventStore()

    var cameraState = PermissionState.unknown
    var calendarState = PermissionState.unknown

    init() {
        refreshStates()
    }

    func refreshStates() {
        cameraState = currentCameraState()
        calendarState = currentCalendarState()
    }

    func requestCameraIfNeeded() {
        guard cameraState.action == .requestCamera else {
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStates()
            }
        }
    }

    func requestCalendarFullAccessIfNeeded() {
        guard calendarState.action == .requestCalendarFullAccess else {
            return
        }

        calendarEventStore.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshStates()
            }
        }
    }

    private func currentCameraState() -> PermissionState {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined(action: .requestCamera)
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private func currentCalendarState() -> PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .calendarFullAccess()
        case .writeOnly:
            return .calendarWriteOnly(action: .requestCalendarFullAccess)
        case .notDetermined:
            return .notDetermined(action: .requestCalendarFullAccess)
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }
}
