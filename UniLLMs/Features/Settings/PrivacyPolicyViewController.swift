//
//  PrivacyPolicyViewController.swift
//  UniLLMs
//
//  Displays the app privacy policy.
//

import UIKit

final class PrivacyPolicyViewController: UIViewController {
    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: "privacy.title")
        configureView()
        configureTextView()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
    }

    private func configureTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.dataDetectorTypes = [.link]
        textView.textContainerInset = UIEdgeInsets(top: 20.0, left: 16.0, bottom: 32.0, right: 16.0)
        textView.text = String(localized: "privacy.body")
        textView.accessibilityLabel = String(localized: "privacy.title")

        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
