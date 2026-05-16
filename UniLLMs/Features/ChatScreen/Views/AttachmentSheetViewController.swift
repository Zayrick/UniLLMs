//
//  AttachmentSheetViewController.swift
//  UniLLMs
//
//  Attachment sheet presented from the composer's plus button.
//
//  Created by Zayrick on 2026/5/16.
//

import UIKit

final class AttachmentSheetViewController: UIViewController {
    private enum Metrics {
        static let contentHorizontalInset: CGFloat = 20.0
        static let contentVerticalInset: CGFloat = 24.0
        static let grabberTopSpacing: CGFloat = 8.0
        static let titleFontSize: CGFloat = 17.0
    }

    private let titleLabel = UILabel()
    private let placeholderLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        configureContent()
    }

    private func configureContent() {
        titleLabel.text = "Attachments"
        titleLabel.font = .systemFont(ofSize: Metrics.titleFontSize, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.text = "Attachment options will appear here."
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.numberOfLines = 0
        placeholderLabel.textAlignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Metrics.contentVerticalInset
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Metrics.contentHorizontalInset
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Metrics.contentHorizontalInset
            ),

            placeholderLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: Metrics.grabberTopSpacing
            ),
            placeholderLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Metrics.contentHorizontalInset
            ),
            placeholderLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Metrics.contentHorizontalInset
            )
        ])
    }
}
