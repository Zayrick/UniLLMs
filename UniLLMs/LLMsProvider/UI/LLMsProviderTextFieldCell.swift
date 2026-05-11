//
//  LLMsProviderTextFieldCell.swift
//  UniLLMs
//
//  Provides the reusable text input cell used by provider configuration screens.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class LLMsProviderTextFieldCell: UITableViewCell {
    static let reuseIdentifier = "LLMsProviderTextFieldCell"

    private let contentStackView = UIStackView()
    private let fieldTitleLabel = UILabel()
    private let textField = UITextField()

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
        textField.text = nil
        textField.placeholder = nil
        textField.isSecureTextEntry = false
        textField.textContentType = nil
    }

    func configure(
        title: String,
        text: String,
        placeholder: String,
        isSecureTextEntry: Bool,
        keyboardType: UIKeyboardType,
        textContentType: UITextContentType?
    ) {
        fieldTitleLabel.text = title
        textField.text = text
        textField.placeholder = placeholder
        textField.isSecureTextEntry = isSecureTextEntry
        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
    }

    func activateTextField() {
        textField.becomeFirstResponder()
    }

    private func configure() {
        selectionStyle = .none

        contentStackView.axis = .horizontal
        contentStackView.alignment = .firstBaseline
        contentStackView.spacing = UIStackView.spacingUseSystem
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        fieldTitleLabel.font = .preferredFont(forTextStyle: .body)
        fieldTitleLabel.adjustsFontForContentSizeCategory = true
        fieldTitleLabel.textColor = .label
        fieldTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        fieldTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textAlignment = .right
        textField.returnKeyType = .done
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        contentStackView.addArrangedSubview(fieldTitleLabel)
        contentStackView.addArrangedSubview(textField)
        contentView.addSubview(contentStackView)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: margins.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
        ])
    }

    @objc private func textFieldDidChange() {
        onTextChange?(textField.text ?? "")
    }
}

typealias ProviderTextFieldCell = LLMsProviderTextFieldCell
