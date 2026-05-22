//
//  ComposerAddSheetViewController.swift
//  UniLLMs
//
//  Add menu presented from the composer's plus button.
//  Shows composer-level actions such as choosing a prompt or adding input files.
//
//  Created by Zayrick on 2026/5/16.
//

import UIKit

final class ComposerAddSheetViewController: UITableViewController {
    enum Action {
        case systemPrompt
        case camera
        case photoLibrary
        case files
    }

    private enum Row: Int, CaseIterable {
        case systemPrompt
        case camera
        case photoLibrary
        case files

        var action: Action {
            switch self {
            case .systemPrompt:
                return .systemPrompt
            case .camera:
                return .camera
            case .photoLibrary:
                return .photoLibrary
            case .files:
                return .files
            }
        }

        var title: String {
            switch self {
            case .systemPrompt:
                return "System Prompt"
            case .camera:
                return "Camera"
            case .photoLibrary:
                return "Photos"
            case .files:
                return "Files"
            }
        }

        var description: String {
            switch self {
            case .systemPrompt:
                return "Choose reusable instructions."
            case .camera:
                return "Take a new photo."
            case .photoLibrary:
                return "Choose photos."
            case .files:
                return "Attach files."
            }
        }

        var symbolName: String {
            switch self {
            case .systemPrompt:
                return "text.quote"
            case .camera:
                return "camera"
            case .photoLibrary:
                return "photo.on.rectangle.angled"
            case .files:
                return "text.document"
            }
        }
    }

    private static let cellReuseIdentifier = "ComposerAddActionCell"

    var onAction: ((Action) -> Void)?

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Add"
        // Required for the sheet transition; without this, the background overpaints during presentation.
        view.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72.0
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: Self.cellReuseIdentifier,
            for: indexPath
        )
        guard let row = Row(rawValue: indexPath.row) else {
            return cell
        }

        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: row.symbolName)
        content.text = row.title
        content.secondaryText = row.description
        content.imageProperties.tintColor = .label

        cell.backgroundConfiguration = .clear()
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        cell.accessoryType = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let row = Row(rawValue: indexPath.row) else {
            return
        }
        handleAction(row.action)
    }

    private func handleAction(_ action: Action) {
        let handler = onAction
        dismiss(animated: true) {
            handler?(action)
        }
    }
}
