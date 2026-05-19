//
//  SystemPromptEditorViewController.swift
//  UniLLMs
//
//  Edits a saved system prompt.
//  Created by Codex on 2026/5/19.
//

import UIKit

final class SystemPromptEditorViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case metadata
        case content
    }

    private enum MetadataRow: Int, CaseIterable {
        case title
    }

    private let dependencies: AppDependencyContainer
    private var saveButtonItem: UIBarButtonItem?
    private var prompt: SystemPromptRecord
    private var savedPrompt: SystemPromptRecord
    private var isNewPrompt: Bool
    private var titleText: String
    private var contentText: String

    init(
        prompt: SystemPromptRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewPrompt: Bool = false
    ) {
        self.prompt = prompt
        savedPrompt = prompt
        self.isNewPrompt = isNewPrompt
        self.dependencies = dependencies
        titleText = prompt.title
        contentText = prompt.content
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        self.dependencies = dependencies
        prompt = dependencies.systemPromptManager.makePromptDraft()
        savedPrompt = prompt
        isNewPrompt = true
        titleText = prompt.title
        contentText = prompt.content
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = isNewPrompt ? "New System Prompt" : prompt.displayTitle
        tableView.register(
            ProviderTextFieldCell.self,
            forCellReuseIdentifier: ProviderTextFieldCell.reuseIdentifier
        )
        tableView.register(
            SystemPromptTextViewCell.self,
            forCellReuseIdentifier: SystemPromptTextViewCell.reuseIdentifier
        )
        configureSaveButton()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .metadata:
            return MetadataRow.allCases.count
        case .content:
            return 1
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .metadata:
            return metadataCell(for: indexPath)
        case .content:
            return contentCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch section {
        case .metadata:
            (tableView.cellForRow(at: indexPath) as? ProviderTextFieldCell)?.activateTextField()
        case .content:
            (tableView.cellForRow(at: indexPath) as? SystemPromptTextViewCell)?.activateTextView()
        }
    }

    private func metadataCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let row = MetadataRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        switch row {
        case .title:
            return textFieldCell(
                title: "Title",
                text: titleText,
                placeholder: "Example: Translation Assistant"
            ) { [weak self] text in
                self?.titleText = text
                self?.updateAfterFieldChange()
            }
        }
    }

    private func textFieldCell(
        title: String,
        text: String,
        placeholder: String,
        onChange: @escaping (String) -> Void
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderTextFieldCell.reuseIdentifier
        ) as? ProviderTextFieldCell else {
            return UITableViewCell()
        }

        cell.configure(
            title: title,
            text: text,
            placeholder: placeholder,
            isSecureTextEntry: false,
            keyboardType: .default,
            textContentType: nil
        )
        cell.onTextChange = onChange
        return cell
    }

    private func contentCell() -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SystemPromptTextViewCell.reuseIdentifier
        ) as? SystemPromptTextViewCell else {
            return UITableViewCell()
        }

        cell.configure(
            title: "Content",
            text: contentText,
            placeholder: "Enter system prompt content"
        )
        cell.onTextChange = { [weak self] text in
            self?.contentText = text
            self?.updateAfterFieldChange()
        }
        return cell
    }

    private func configureSaveButton() {
        let saveItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(savePrompt)
        )
        saveButtonItem = saveItem
        updateSaveButtonState()
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
        isNewPrompt = false
        savedPrompt = prompt
        title = prompt.displayTitle
        updateSaveButtonState()
        navigationController?.popViewController(animated: true)
    }

    private func updateAfterFieldChange() {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmedTitle.isEmpty ? (isNewPrompt ? "New System Prompt" : savedPrompt.displayTitle) : trimmedTitle
        updateSaveButtonState()
    }

    private func updateSaveButtonState() {
        navigationItem.rightBarButtonItem = canSavePrompt ? saveButtonItem : nil
    }

    private var canSavePrompt: Bool {
        promptForSaving != nil && (isNewPrompt || hasUnsavedChanges)
    }

    private var hasUnsavedChanges: Bool {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle != savedPrompt.title || trimmedContent != savedPrompt.content
    }

    private var promptForSaving: SystemPromptRecord? {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              !trimmedContent.isEmpty else {
            return nil
        }

        var updatedPrompt = prompt
        updatedPrompt.title = trimmedTitle
        updatedPrompt.content = trimmedContent
        return updatedPrompt
    }
}

private final class SystemPromptTextViewCell: UITableViewCell {
    static let reuseIdentifier = "SystemPromptTextViewCell"

    private let contentStackView = UIStackView()
    private let fieldTitleLabel = UILabel()
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
        fieldTitleLabel.text = nil
        textView.text = ""
        placeholderLabel.text = nil
        updatePlaceholderVisibility()
    }

    func configure(
        title: String,
        text: String,
        placeholder: String
    ) {
        fieldTitleLabel.text = title
        textView.text = text
        placeholderLabel.text = placeholder
        updatePlaceholderVisibility()
    }

    func activateTextView() {
        textView.becomeFirstResponder()
    }

    private func configure() {
        selectionStyle = .none

        contentStackView.axis = .vertical
        contentStackView.spacing = 8
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        fieldTitleLabel.font = .preferredFont(forTextStyle: .body)
        fieldTitleLabel.adjustsFontForContentSizeCategory = true
        fieldTitleLabel.textColor = .label

        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.layer.borderWidth = 0
        textView.layer.cornerRadius = 0
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.isScrollEnabled = true
        textView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.addSubview(placeholderLabel)
        contentStackView.addArrangedSubview(fieldTitleLabel)
        contentStackView.addArrangedSubview(textView)
        contentView.addSubview(contentStackView)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: margins.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -5)
        ])
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
    }
}

extension SystemPromptTextViewCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        onTextChange?(textView.text)
    }
}
