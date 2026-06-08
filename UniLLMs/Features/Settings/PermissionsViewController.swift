//
//  PermissionsViewController.swift
//  UniLLMs
//
//  Displays app permission status and permission-related shortcuts.
//

import AVFoundation
import EventKit
import UIKit

final class PermissionsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case media
        case calendar
        case shortcuts

        var title: String {
            switch self {
            case .media:
                return String(localized: "permissions.section.media")
            case .calendar:
                return String(localized: "permissions.section.calendar")
            case .shortcuts:
                return String(localized: "permissions.section.shortcuts")
            }
        }
    }

    private enum MediaRow: Int, CaseIterable {
        case camera
        case photoPicker

        var title: String {
            switch self {
            case .camera:
                return String(localized: "permissions.camera.title")
            case .photoPicker:
                return String(localized: "permissions.photos_picker.title")
            }
        }

        var detail: String {
            switch self {
            case .camera:
                return String(localized: "permissions.camera.detail")
            case .photoPicker:
                return String(localized: "permissions.photos_picker.detail")
            }
        }

        var symbolName: String {
            switch self {
            case .camera:
                return "camera"
            case .photoPicker:
                return "photo.on.rectangle.angled"
            }
        }

        var iconTintColor: UIColor {
            switch self {
            case .camera:
                return .systemBlue
            case .photoPicker:
                return .systemPink
            }
        }
    }

    private enum CalendarRow: Int, CaseIterable {
        case events

        var title: String {
            String(localized: "permissions.calendar.title")
        }

        var detail: String {
            String(localized: "permissions.calendar.detail")
        }

        var symbolName: String {
            "calendar"
        }

        var iconTintColor: UIColor {
            .systemOrange
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

        static let notDetermined = PermissionState(
            title: String(localized: "permissions.status.not_determined"),
            tintColor: .secondaryLabel,
            action: .requestCamera,
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

        static func notDeterminedWithAction(_ action: PermissionAction) -> PermissionState {
            PermissionState(
                title: String(localized: "permissions.status.not_determined"),
                tintColor: .secondaryLabel,
                action: action,
                dimsIcon: false
            )
        }
    }

    private enum Metrics {
        static let iconSize = CGSize(width: 28.0, height: 28.0)
    }

    private var didBecomeActiveObservation: NSObjectProtocol?
    private let calendarEventStore = EKEventStore()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        if let didBecomeActiveObservation {
            NotificationCenter.default.removeObserver(didBecomeActiveObservation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: "permissions.title")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68.0

        didBecomeActiveObservation = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadPermissionRows()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadPermissionRows()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .media:
            return MediaRow.allCases.count
        case .calendar:
            return CalendarRow.allCases.count
        case .shortcuts:
            return 1
        case nil:
            return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .media:
            return mediaCell(for: indexPath)
        case .calendar:
            return calendarCell(for: indexPath)
        case .shortcuts:
            return appSettingsCell()
        case nil:
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section) {
        case .media:
            requestCameraIfNeeded(at: indexPath)
        case .calendar:
            requestCalendarFullAccessIfNeeded(at: indexPath)
        case .shortcuts:
            openAppSettings()
        case nil:
            return
        }
    }

    private func mediaCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard let row = MediaRow(rawValue: indexPath.row) else {
            return cell
        }

        let state = permissionState(for: row)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.secondaryText = row.detail
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: row.symbolName)
        content.imageProperties.maximumSize = Metrics.iconSize
        content.imageProperties.reservedLayoutSize = Metrics.iconSize
        content.imageProperties.tintColor = state.dimsIcon ? .tertiaryLabel : row.iconTintColor
        cell.contentConfiguration = content
        cell.accessoryView = statusLabel(for: state)
        cell.selectionStyle = state.action == .none ? .none : .default
        cell.accessibilityLabel = "\(row.title), \(row.detail), \(state.title)"
        return cell
    }

    private func calendarCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard let row = CalendarRow(rawValue: indexPath.row) else {
            return cell
        }

        let state = permissionState(for: row)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.secondaryText = row.detail
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: row.symbolName)
        content.imageProperties.maximumSize = Metrics.iconSize
        content.imageProperties.reservedLayoutSize = Metrics.iconSize
        content.imageProperties.tintColor = state.dimsIcon ? .tertiaryLabel : row.iconTintColor
        cell.contentConfiguration = content
        cell.accessoryView = statusLabel(for: state)
        cell.selectionStyle = state.action == .none ? .none : .default
        cell.accessibilityLabel = "\(row.title), \(row.detail), \(state.title)"
        return cell
    }

    private func appSettingsCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = String(localized: "permissions.open_settings.title")
        content.secondaryText = String(localized: "permissions.open_settings.detail")
        content.image = UIImage(systemName: "gearshape")
        content.imageProperties.tintColor = .systemGray
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func statusLabel(for state: PermissionState) -> UILabel {
        let label = UILabel()
        label.text = state.title
        label.textColor = state.tintColor
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func requestCameraIfNeeded(at indexPath: IndexPath) {
        guard MediaRow(rawValue: indexPath.row) == .camera,
              permissionState(for: .camera).action == .requestCamera else {
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor [viewController = self] in
                viewController?.reloadPermissionRows()
            }
        }
    }

    private func requestCalendarFullAccessIfNeeded(at indexPath: IndexPath) {
        guard CalendarRow(rawValue: indexPath.row) == .events,
              permissionState(for: .events).action == .requestCalendarFullAccess else {
            return
        }

        calendarEventStore.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor [viewController = self] in
                viewController?.reloadPermissionRows()
            }
        }
    }

    private func permissionState(for row: MediaRow) -> PermissionState {
        switch row {
        case .camera:
            return cameraPermissionState()
        case .photoPicker:
            return .notRequired
        }
    }

    private func permissionState(for row: CalendarRow) -> PermissionState {
        switch row {
        case .events:
            return calendarPermissionState()
        }
    }

    private func cameraPermissionState() -> PermissionState {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private func calendarPermissionState() -> PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .calendarFullAccess()
        case .writeOnly:
            return .calendarWriteOnly(action: .requestCalendarFullAccess)
        case .notDetermined:
            return .notDeterminedWithAction(.requestCalendarFullAccess)
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private func reloadPermissionRows() {
        guard isViewLoaded else {
            return
        }
        tableView.reloadSections(
            IndexSet([
                Section.media.rawValue,
                Section.calendar.rawValue
            ]),
            with: .none
        )
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
