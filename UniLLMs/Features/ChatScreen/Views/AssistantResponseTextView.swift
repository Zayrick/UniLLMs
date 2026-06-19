//
//  AssistantResponseTextView.swift
//  UniLLMs
//
//  Displays assistant streaming raw text, reasoning text, loading state, and error messages.
//  Created by Zayrick on 2026/5/11.
//

import Symbols
import UIKit

final class AssistantResponseTextView: UIView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 2.0
        static let verticalInset: CGFloat = 2.0
        static let sectionSpacing: CGFloat = 8.0
        static let loadingSpacing: CGFloat = 7.0
        static let copyButtonSideLength: CGFloat = 30.0
        static let copyIconPointSize: CGFloat = 12.0
        static let copyAppearTranslationY: CGFloat = -8.0
        static let copyAppearAnimationDuration: TimeInterval = 0.46
        static let copyAppearAnimationDampingRatio: CGFloat = 0.88
    }

    private let stackView = UIStackView()
    private let loadingView = UIStackView()
    private let loadingIndicatorView = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let timelineView = AssistantResponseTimelineView()
    private let copyButtonContainerView = UIView()
    private let copyRawButton = CopyRawButton(
        symbolConfiguration: UIImage.SymbolConfiguration(
            pointSize: Metrics.copyIconPointSize,
            weight: .medium
        )
    )
    private let errorLabel = UILabel()
    private var isResponseFinished = false
    private var isLoading = false
    var onLayoutInvalidated: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func appendDisplayPart(_ part: ChatResponseDisplayPart) {
        appendDisplayParts([part])
    }

    func appendToolEvent(_ event: ChatToolEvent) {
        appendDisplayParts([.toolEvent(event)])
    }

    private func appendDisplayParts(_ parts: [ChatResponseDisplayPart]) {
        let visibleParts = parts.filter { !$0.isEmpty }
        guard !visibleParts.isEmpty else {
            return
        }

        isLoading = false
        isResponseFinished = false
        errorLabel.text = nil

        for part in visibleParts {
            timelineView.appendDisplayPart(part)
        }

        updateVisibility()
    }

    func setError(_ message: String) {
        isLoading = false
        isResponseFinished = true
        timelineView.finishStreamingContent()
        errorLabel.text = message
        updateVisibility()
    }

    func appendStoredError(_ message: String) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        isLoading = false
        isResponseFinished = true
        timelineView.finishStreamingContent()
        errorLabel.text = message
        updateVisibility()
    }

    func showLoadingIfNeeded() {
        guard timelineView.isEmpty,
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
        isResponseFinished = true
        timelineView.finishStreamingContent()
        updateVisibility()
    }

    func prepareForStreamingResponse() {
        timelineView.prepareTimelineRendering()
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
        configureTimelineView()
        configureCopyRawButton()
        configureLabel(errorLabel, textStyle: .callout, color: .systemRed)

        stackView.addArrangedSubview(loadingView)
        stackView.addArrangedSubview(timelineView)
        stackView.addArrangedSubview(copyButtonContainerView)
        stackView.addArrangedSubview(errorLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalInset),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.verticalInset)
        ])

        updateVisibility()
    }

    private func configureLoadingView() {
        loadingView.axis = .horizontal
        loadingView.alignment = .center
        loadingView.spacing = Metrics.loadingSpacing
        loadingView.isAccessibilityElement = true
        loadingView.accessibilityLabel = String(localized: .chatGeneratingResponse)
        loadingView.accessibilityTraits = .updatesFrequently
        loadingView.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicatorView.color = .secondaryLabel
        loadingIndicatorView.hidesWhenStopped = true
        loadingIndicatorView.isAccessibilityElement = false
        loadingIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
        loadingIndicatorView.setContentCompressionResistancePriority(.required, for: .horizontal)

        loadingLabel.text = String(localized: .chatGeneratingResponse)
        configureLabel(loadingLabel, textStyle: .callout, color: .secondaryLabel)
        loadingLabel.isAccessibilityElement = false

        loadingView.addArrangedSubview(loadingIndicatorView)
        loadingView.addArrangedSubview(loadingLabel)
    }

    private func configureTimelineView() {
        timelineView.onLayoutInvalidated = { [weak self] in
            self?.invalidateResponseLayout()
        }
        timelineView.translatesAutoresizingMaskIntoConstraints = false
    }

    func appendStoredReasoning(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        appendDisplayParts([.reasoning(text)])
    }

    func appendStoredRawText(_ rawText: String) {
        guard !rawText.isEmpty else {
            return
        }

        isLoading = false
        isResponseFinished = false
        errorLabel.text = nil
        timelineView.appendStoredRawText(rawText)
        updateVisibility()
    }

    private func configureCopyRawButton() {
        copyButtonContainerView.backgroundColor = .clear
        copyButtonContainerView.isOpaque = false
        copyButtonContainerView.setContentCompressionResistancePriority(.required, for: .vertical)
        copyButtonContainerView.setContentHuggingPriority(.required, for: .vertical)
        copyButtonContainerView.translatesAutoresizingMaskIntoConstraints = false

        copyRawButton.translatesAutoresizingMaskIntoConstraints = false
        copyRawButton.addTarget(
            self,
            action: #selector(copyRawText),
            for: .touchUpInside
        )
        copyButtonContainerView.addSubview(copyRawButton)

        NSLayoutConstraint.activate([
            copyRawButton.topAnchor.constraint(equalTo: copyButtonContainerView.topAnchor),
            copyRawButton.leadingAnchor.constraint(equalTo: copyButtonContainerView.leadingAnchor),
            copyRawButton.bottomAnchor.constraint(equalTo: copyButtonContainerView.bottomAnchor),
            copyRawButton.trailingAnchor.constraint(
                lessThanOrEqualTo: copyButtonContainerView.trailingAnchor
            ),
            copyRawButton.widthAnchor.constraint(equalToConstant: Metrics.copyButtonSideLength),
            copyRawButton.heightAnchor.constraint(equalToConstant: Metrics.copyButtonSideLength)
        ])
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

        timelineView.isHidden = timelineView.isEmpty
        let shouldShowCopyButton = shouldShowCopyRawButton
        let shouldAnimateCopyButtonAppearance = copyButtonContainerView.isHidden && shouldShowCopyButton
        copyButtonContainerView.isHidden = !shouldShowCopyButton
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        isHidden = !isLoading && timelineView.isEmpty && errorLabel.isHidden
        invalidateResponseLayout()

        if shouldAnimateCopyButtonAppearance {
            animateCopyRawButtonAppearance()
        }
    }

    private var shouldShowCopyRawButton: Bool {
        isResponseFinished && !timelineView.rawText.isEmpty
    }

    @objc private func copyRawText() {
        guard !timelineView.rawText.isEmpty else {
            return
        }

        UIPasteboard.general.string = timelineView.rawText
        copyRawButton.showCopiedFeedback()
    }

    private func animateCopyRawButtonAppearance() {
        copyRawButton.playAppearAnimation()

        guard window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            copyButtonContainerView.alpha = 1.0
            copyButtonContainerView.transform = .identity
            return
        }

        copyButtonContainerView.alpha = 0.0
        copyButtonContainerView.transform = CGAffineTransform(
            translationX: 0.0,
            y: Metrics.copyAppearTranslationY
        )

        let animator = UIViewPropertyAnimator(
            duration: Metrics.copyAppearAnimationDuration,
            dampingRatio: Metrics.copyAppearAnimationDampingRatio
        ) {
            self.copyButtonContainerView.alpha = 1.0
            self.copyButtonContainerView.transform = .identity
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.addCompletion { _ in
            self.copyButtonContainerView.alpha = 1.0
            self.copyButtonContainerView.transform = .identity
        }
        animator.startAnimation()
    }

    private func invalidateResponseLayout() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onLayoutInvalidated?()
    }

    private final class CopyRawButton: UIButton {
        private enum SymbolName {
            static let copy = "square.on.square"
            static let copied = "checkmark"
        }

        private let symbolConfiguration: UIImage.SymbolConfiguration
        private var isShowingFeedback = false

        init(symbolConfiguration: UIImage.SymbolConfiguration) {
            self.symbolConfiguration = symbolConfiguration
            super.init(frame: .zero)
            configure()
        }

        required init?(coder: NSCoder) {
            symbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: Metrics.copyIconPointSize,
                weight: .medium
            )
            super.init(coder: coder)
            configure()
        }

        func showCopiedFeedback() {
            guard !isShowingFeedback else {
                return
            }

            isShowingFeedback = true
            isUserInteractionEnabled = false
            accessibilityLabel = String(localized: .generalCopied)

            setSymbol(named: SymbolName.copied, animated: true) { [weak self] in
                guard let self else {
                    return
                }

                self.setSymbol(named: SymbolName.copy, animated: true) { [weak self] in
                    self?.accessibilityLabel = String(localized: .assistantCopyRaw)
                    self?.isUserInteractionEnabled = true
                    self?.isShowingFeedback = false
                }
            }
        }

        func playAppearAnimation() {
            guard window != nil,
                  !UIAccessibility.isReduceMotionEnabled else {
                return
            }

            imageView?.addSymbolEffect(
                .appear.up.wholeSymbol,
                options: .nonRepeating,
                animated: true
            )
        }

        private func configure() {
            backgroundColor = .clear
            isOpaque = false
            accessibilityLabel = String(localized: .assistantCopyRaw)
            tintColor = .tertiaryLabel

            setSymbol(named: SymbolName.copy, animated: false)
        }

        private func setSymbol(
            named systemName: String,
            animated: Bool,
            completion: (() -> Void)? = nil
        ) {
            guard let image = UIImage(systemName: systemName, withConfiguration: symbolConfiguration) else {
                completion?()
                return
            }

            guard animated,
                  window != nil,
                  let imageView,
                  !UIAccessibility.isReduceMotionEnabled else {
                setButtonImage(image)
                completion?()
                return
            }

            imageView.setSymbolImage(
                image,
                contentTransition: ReplaceSymbolEffect.downUp
            ) { [weak self] context in
                guard let self else {
                    return
                }

                self.setButtonImage(image)
                completion?()
            }
        }

        private func setButtonImage(_ image: UIImage) {
            var buttonConfiguration = configuration ?? .plain()
            buttonConfiguration.image = image
            buttonConfiguration.baseForegroundColor = .tertiaryLabel
            buttonConfiguration.contentInsets = .zero
            configuration = buttonConfiguration
        }
    }
}

private final class AssistantResponseTimelineView: UIView {
    private let hostView = StreamingContentHostView()
    private var hasContent = false

    var onLayoutInvalidated: (() -> Void)?

    private(set) var rawText = ""

    var isEmpty: Bool {
        !hasContent
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func appendDisplayPart(_ part: ChatResponseDisplayPart) {
        guard !part.isEmpty else {
            return
        }

        switch part {
        case let .reasoning(text):
            hostView.appendTimelineReasoning(text)
        case let .rawText(rawText):
            appendRawText(rawText)
        case let .toolEvent(event):
            hostView.appendTimelineToolEvent(event)
        }

        hasContent = true
        invalidateTimelineLayout()
    }

    func prepareTimelineRendering() {
        hostView.prepareTimelineRendering()
    }

    func appendStoredRawText(_ rawText: String) {
        guard !rawText.isEmpty else {
            return
        }

        appendRawText(rawText)
        invalidateTimelineLayout()
    }

    func finishStreamingContent() {
        hostView.finishTimelineRendering()
        invalidateTimelineLayout()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)

        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.onLayoutInvalidated = { [weak self] in
            self?.invalidateTimelineLayout()
        }
        addSubview(hostView)

        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: topAnchor),
            hostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func appendRawText(_ rawTextDelta: String) {
        guard !rawTextDelta.isEmpty else {
            return
        }

        rawText += rawTextDelta
        hasContent = true
        hostView.appendTimelineRawText(rawTextDelta)
    }

    private func invalidateTimelineLayout() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onLayoutInvalidated?()
    }
}
