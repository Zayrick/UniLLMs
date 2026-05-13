//
//  AssistantResponseTextView.swift
//  UniLLMs
//
//  Displays assistant streaming content, reasoning text, loading state, and error messages.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class AssistantResponseTextView: UIView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 2.0
        static let verticalInset: CGFloat = 2.0
        static let sectionSpacing: CGFloat = 8.0
        static let loadingSpacing: CGFloat = 7.0
    }

    private let stackView = UIStackView()
    private let loadingView = UIStackView()
    private let loadingIndicatorView = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let reasoningTextView = StreamingTextView()
    private let contentMarkdownView = StreamingMarkdownView()
    private let errorLabel = UILabel()
    private var reasoningHeightConstraint: NSLayoutConstraint!
    private var contentHeightConstraint: NSLayoutConstraint!
    private var hasReasoningText = false
    private var hasContentText = false
    private var isLoading = false
    private var lastMeasuredTextWidth: CGFloat = 0.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextViewHeightsIfNeeded()
    }

    func append(content contentDelta: String, reasoning reasoningDelta: String) {
        guard !contentDelta.isEmpty || !reasoningDelta.isEmpty else {
            return
        }

        isLoading = false
        errorLabel.text = nil

        if !reasoningDelta.isEmpty {
            hasReasoningText = true
            reasoningTextView.append(reasoningDelta, attributes: reasoningAttributes)
        }
        if !contentDelta.isEmpty {
            hasContentText = true
            contentMarkdownView.appendMarkdown(contentDelta)
        }

        updateVisibility()
    }

    func setError(_ message: String) {
        isLoading = false
        contentMarkdownView.finishStreamingContent()
        errorLabel.text = message
        updateVisibility()
    }

    func showLoadingIfNeeded() {
        guard !hasReasoningText,
              !hasContentText,
              (errorLabel.text ?? "").isEmpty else {
            return
        }

        isLoading = true
        updateVisibility()
    }

    func setLoadingVisible(_ isVisible: Bool) {
        guard isLoading != isVisible else {
            return
        }

        isLoading = isVisible
        updateVisibility()
    }

    func finishStreamingContent() {
        contentMarkdownView.finishStreamingContent()
        updateVisibility()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Metrics.sectionSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        configureLoadingView()

        configurePlainTextView(reasoningTextView, textStyle: .callout, color: .secondaryLabel)
        configureContentMarkdownView()
        configureLabel(errorLabel, textStyle: .callout, color: .systemRed)

        stackView.addArrangedSubview(loadingView)
        stackView.addArrangedSubview(reasoningTextView)
        stackView.addArrangedSubview(contentMarkdownView)
        stackView.addArrangedSubview(errorLabel)

        reasoningHeightConstraint = reasoningTextView.heightAnchor.constraint(equalToConstant: 0.0)
        contentHeightConstraint = contentMarkdownView.heightAnchor.constraint(equalToConstant: 0.0)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalInset),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.verticalInset),
            reasoningHeightConstraint,
            contentHeightConstraint
        ])

        updateVisibility()
    }

    private func configureLoadingView() {
        loadingView.axis = .horizontal
        loadingView.alignment = .center
        loadingView.spacing = Metrics.loadingSpacing
        loadingView.isAccessibilityElement = true
        loadingView.accessibilityLabel = "Generating response"
        loadingView.accessibilityTraits = .updatesFrequently
        loadingView.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicatorView.color = .secondaryLabel
        loadingIndicatorView.hidesWhenStopped = true
        loadingIndicatorView.isAccessibilityElement = false
        loadingIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
        loadingIndicatorView.setContentCompressionResistancePriority(.required, for: .horizontal)

        loadingLabel.text = "Generating response"
        configureLabel(loadingLabel, textStyle: .callout, color: .secondaryLabel)
        loadingLabel.isAccessibilityElement = false

        loadingView.addArrangedSubview(loadingIndicatorView)
        loadingView.addArrangedSubview(loadingLabel)
    }

    private func configureTextView(_ textView: UITextView) {
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = [.link]
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0.0
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configurePlainTextView(
        _ textView: UITextView,
        textStyle: UIFont.TextStyle,
        color: UIColor
    ) {
        configureTextView(textView)
        textView.font = .preferredFont(forTextStyle: textStyle)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = color
    }

    private func configureContentMarkdownView() {
        contentMarkdownView.backgroundColor = .clear
        contentMarkdownView.isOpaque = false
        contentMarkdownView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentMarkdownView.setContentHuggingPriority(.required, for: .vertical)
        contentMarkdownView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLabel(
        _ label: UILabel,
        textStyle: UIFont.TextStyle,
        color: UIColor
    ) {
        label.font = .preferredFont(forTextStyle: textStyle)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateVisibility() {
        loadingView.isHidden = !isLoading
        if isLoading {
            loadingIndicatorView.startAnimating()
        } else {
            loadingIndicatorView.stopAnimating()
        }

        reasoningTextView.isHidden = !hasReasoningText
        contentMarkdownView.isHidden = !hasContentText
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        isHidden = !isLoading && !hasReasoningText && !hasContentText && errorLabel.isHidden
        updateTextViewHeights()
    }

    private func updateTextViewHeightsIfNeeded() {
        let width = textMeasurementWidth
        guard abs(width - lastMeasuredTextWidth) > 0.5 else {
            return
        }

        updateTextViewHeights()
    }

    private func updateTextViewHeights() {
        let width = textMeasurementWidth
        guard width > 0.0 else {
            return
        }

        updateTextViewHeight(reasoningTextView, constraint: reasoningHeightConstraint, width: width)
        updateContentHeight(contentMarkdownView, constraint: contentHeightConstraint, width: width)
        lastMeasuredTextWidth = width
        invalidateIntrinsicContentSize()
    }

    private func updateTextViewHeight(
        _ textView: UITextView,
        constraint: NSLayoutConstraint,
        width: CGFloat
    ) {
        guard !textView.isHidden else {
            constraint.constant = 0.0
            return
        }

        let fittingSize = textView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        constraint.constant = ceil(fittingSize.height)
    }

    private func updateContentHeight(
        _ view: UIView,
        constraint: NSLayoutConstraint,
        width: CGFloat
    ) {
        guard !view.isHidden else {
            constraint.constant = 0.0
            return
        }

        let fittingSize = view.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        constraint.constant = ceil(fittingSize.height)
    }

    private var textMeasurementWidth: CGFloat {
        max(
            stackView.bounds.width,
            bounds.width - Metrics.horizontalInset * 2.0,
            (superview?.bounds.width ?? 0.0) - Metrics.horizontalInset * 2.0,
            1.0
        )
    }

    private var reasoningAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .callout),
            .foregroundColor: UIColor.secondaryLabel
        ]
    }

    private final class StreamingTextView: UITextView {
        func append(_ string: String, attributes: [NSAttributedString.Key: Any]) {
            guard !string.isEmpty else {
                return
            }

            textStorage.beginEditing()
            textStorage.append(NSAttributedString(string: string, attributes: attributes))
            textStorage.endEditing()
            invalidateIntrinsicContentSize()
        }
    }
}
