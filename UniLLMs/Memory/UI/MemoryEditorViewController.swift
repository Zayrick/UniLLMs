//
//  MemoryEditorViewController.swift
//  UniLLMs
//
//  Edits a saved long-term memory.
//  Created by Codex on 2026/6/1.
//

import UIKit

final class MemoryEditorViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case memory

        var headerTitle: String? {
            "Memory"
        }

        var footerTitle: String? {
            "Memories help the assistant personalize future replies. You can edit or delete them anytime."
        }
    }

    private let dependencies: AppDependencyContainer
    private var memory: MemoryRecord
    private var savedMemory: MemoryRecord
    private var isNewMemory: Bool
    private var memoryText: String
    private var saveTask: Task<Void, Never>?

    private lazy var saveButtonItem = UIBarButtonItem(
        barButtonSystemItem: .save,
        target: self,
        action: #selector(saveMemory)
    )

    init(
        memory: MemoryRecord,
        dependencies: AppDependencyContainer = AppEnvironment.shared.dependencies,
        isNewMemory: Bool = false
    ) {
        self.memory = memory
        savedMemory = memory
        self.isNewMemory = isNewMemory
        self.dependencies = dependencies
        memoryText = memory.text
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        let dependencies = AppEnvironment.shared.dependencies
        self.dependencies = dependencies
        memory = dependencies.memoryManager.makeMemoryDraft()
        savedMemory = memory
        isNewMemory = true
        memoryText = memory.text
        super.init(coder: coder)
    }

    deinit {
        saveTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = navigationTitle
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = saveButtonItem
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 220
        tableView.register(
            MemoryTextViewCell.self,
            forCellReuseIdentifier: MemoryTextViewCell.reuseIdentifier
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
        memoryCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let cell = tableView.cellForRow(at: indexPath) as? MemoryTextViewCell else {
            return
        }

        cell.activateTextView()
    }

    private func memoryCell() -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: MemoryTextViewCell.reuseIdentifier
        ) as? MemoryTextViewCell else {
            return UITableViewCell()
        }

        cell.configure(
            text: memoryText,
            placeholder: "I prefer concise answers."
        )
        cell.onTextChange = { [weak self] text in
            self?.memoryText = text
            self?.updateAfterFieldChange()
        }
        return cell
    }

    @objc private func saveMemory() {
        view.endEditing(true)
        guard var memoryForSaving else {
            updateSaveButtonState()
            return
        }

        let now = Date()
        if isNewMemory {
            memoryForSaving.createdAt = now
        }
        memoryForSaving.updatedAt = now
        saveButtonItem.isEnabled = false

        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.dependencies.memoryManager.saveMemory(memoryForSaving)
                self.memory = memoryForSaving
                self.savedMemory = memoryForSaving
                self.isNewMemory = false
                self.title = self.navigationTitle
                self.updateSaveButtonState()
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.updateSaveButtonState()
            }
        }
    }

    private func updateAfterFieldChange() {
        title = navigationTitle
        updateSaveButtonState()
    }

    private func updateSaveButtonState() {
        saveButtonItem.isEnabled = canSaveMemory
    }

    private var navigationTitle: String {
        isNewMemory ? "New Memory" : "Memory"
    }

    private var canSaveMemory: Bool {
        guard let memoryForSaving else {
            return false
        }

        return isNewMemory || memoryForSaving != savedMemory
    }

    private var memoryForSaving: MemoryRecord? {
        let trimmedText = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        var updatedMemory = memory
        updatedMemory.scope = .user
        updatedMemory.text = trimmedText
        return updatedMemory
    }
}

private final class MemoryTextViewCell: UITableViewCell {
    static let reuseIdentifier = "MemoryTextViewCell"

    private enum Layout {
        static let minimumHeight: CGFloat = 220
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
        textView.accessibilityLabel = "Memory"
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

extension MemoryTextViewCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        onTextChange?(textView.text)
    }
}
