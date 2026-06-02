//
//  SystemPromptEditorViewController.swift
//  UniLLMs
//
//  Edits a saved system prompt.
//  Created by Zayrick on 2026/5/19.
//

import UIKit

final class SystemPromptEditorViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case name
        case prompt

        var headerTitle: String? {
            self == .prompt ? String(localized: .systemPromptsPrompt) : nil
        }

        var footerTitle: String? {
            switch self {
            case .name:
                return nil
            case .prompt:
                return String(localized: .systemPromptsPromptFooter)
            }
        }
    }

    private let dependencies: AppDependencyContainer
    private var prompt: SystemPromptRecord
    private var savedPrompt: SystemPromptRecord
    private var isNewPrompt: Bool
    private var nameText: String
    private var promptText: String

    private lazy var saveButtonItem = UIBarButtonItem(
        barButtonSystemItem: .save,
        target: self,
        action: #selector(savePrompt)
    )

    init(
        prompt: SystemPromptRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewPrompt: Bool = false
    ) {
        self.prompt = prompt
        savedPrompt = prompt
        self.isNewPrompt = isNewPrompt
        self.dependencies = dependencies
        nameText = prompt.title
        promptText = prompt.content
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        self.dependencies = dependencies
        prompt = dependencies.systemPromptManager.makePromptDraft()
        savedPrompt = prompt
        isNewPrompt = true
        nameText = prompt.title
        promptText = prompt.content
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = navigationTitle
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = saveButtonItem
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.register(
            ProviderTextFieldCell.self,
            forCellReuseIdentifier: ProviderTextFieldCell.reuseIdentifier
        )
        tableView.register(
            SystemPromptTextViewCell.self,
            forCellReuseIdentifier: SystemPromptTextViewCell.reuseIdentifier
        )
        updateSaveButtonState()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.headerTitle
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section)?.footerTitle
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .some(.name):
            return nameCell()
        case .some(.prompt):
            return promptCell()
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch tableView.cellForRow(at: indexPath) {
        case let cell as ProviderTextFieldCell:
            cell.activateTextField()
        case let cell as SystemPromptTextViewCell:
            cell.activateTextView()
        default:
            break
        }
    }

    private func nameCell() -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderTextFieldCell.reuseIdentifier
        ) as? ProviderTextFieldCell else {
            return UITableViewCell()
        }

        cell.configure(
            title: String(localized: .providerFieldName),
            text: nameText,
            placeholder: String(localized: .systemPromptsNamePlaceholder),
            isSecureTextEntry: false,
            keyboardType: .default,
            textContentType: nil
        )
        cell.onTextChange = { [weak self] text in
            self?.nameText = text
            self?.updateAfterFieldChange()
        }
        return cell
    }

    private func promptCell() -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SystemPromptTextViewCell.reuseIdentifier
        ) as? SystemPromptTextViewCell else {
            return UITableViewCell()
        }

        cell.configure(
            text: promptText,
            placeholder: String(localized: .systemPromptsPromptPlaceholder)
        )
        cell.onTextChange = { [weak self] text in
            self?.promptText = text
            self?.updateAfterFieldChange()
        }
        return cell
    }

    @objc private func savePrompt() {
        view.endEditing(true)
        guard var promptForSaving else {
            updateSaveButtonState()
            return
        }

        promptForSaving.updatedAt = Date()
        prompt = promptForSaving
        dependencies.systemPromptManager.savePrompt(prompt)
        savedPrompt = prompt
        isNewPrompt = false
        title = prompt.displayTitle
        updateSaveButtonState()
        navigationController?.popViewController(animated: true)
    }

    private func updateAfterFieldChange() {
        title = navigationTitle
        updateSaveButtonState()
    }

    private func updateSaveButtonState() {
        saveButtonItem.isEnabled = canSavePrompt
    }

    private var navigationTitle: String {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        return isNewPrompt ? String(localized: .systemPromptsNewPrompt) : savedPrompt.displayTitle
    }

    private var canSavePrompt: Bool {
        guard let promptForSaving else {
            return false
        }

        return isNewPrompt || promptForSaving != savedPrompt
    }

    private var promptForSaving: SystemPromptRecord? {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedPrompt.isEmpty else {
            return nil
        }

        var updatedPrompt = prompt
        updatedPrompt.title = trimmedName
        updatedPrompt.content = trimmedPrompt
        return updatedPrompt
    }
}

private final class SystemPromptTextViewCell: UITableViewCell {
    static let reuseIdentifier = "SystemPromptTextViewCell"

    private enum Layout {
        static let minimumHeight: CGFloat = 180
    }

    private let textView = UITextView()
    private let placeholderLabel = UILabel()

    var onTextChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        onTextChange = nil
        textView.text = ""
        placeholderLabel.text = nil
        updatePlaceholderVisibility()
    }

    func configure(text: String, placeholder: String) {
        textView.text = text
        placeholderLabel.text = placeholder
        updatePlaceholderVisibility()
    }

    func activateTextView() {
        textView.becomeFirstResponder()
    }

    private func configure() {
        selectionStyle = .none

        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = String(localized: .systemPromptsPrompt)
        textView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(textView)
        contentView.addSubview(placeholderLabel)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: margins.topAnchor),
            textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumHeight),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor)
        ])
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}

extension SystemPromptTextViewCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        onTextChange?(textView.text)
    }
}
