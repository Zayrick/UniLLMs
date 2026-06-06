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

    private enum TimelineSegmentKind {
        case thinking
        case rawText
    }

    private struct TimelineSegment {
        var kind: TimelineSegmentKind
        var view: UIView
        var heightConstraint: NSLayoutConstraint?
    }

    private let stackView = UIStackView()
    private let loadingView = UIStackView()
    private let loadingIndicatorView = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let timelineStackView = UIStackView()
    private let copyButtonContainerView = UIView()
    private let copyRawButton = CopyRawButton(
        symbolConfiguration: UIImage.SymbolConfiguration(
            pointSize: Metrics.copyIconPointSize,
            weight: .medium
        )
    )
    private let errorLabel = UILabel()
    private var timelineSegments: [TimelineSegment] = []
    private var isResponseFinished = false
    private var rawText = ""
    private var isLoading = false
    private var lastMeasuredContentWidth: CGFloat = 0.0
    private weak var activeThinkingSection: ThinkingSectionView?
    private var toolSectionsByCallID: [String: ThinkingSectionView] = [:]

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
        updateContentViewHeightsIfNeeded()
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
            appendDisplayPartWithoutUpdatingVisibility(part)
        }

        updateVisibility()
    }

    func setError(_ message: String) {
        isLoading = false
        isResponseFinished = true
        finishRawTextTimelineSegments()
        finishAllThinkingSections(animated: true)
        errorLabel.text = message
        updateVisibility()
    }

    func showLoadingIfNeeded() {
        guard timelineSegments.isEmpty,
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
        finishRawTextTimelineSegments()
        finishAllThinkingSections(animated: true)
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
        configureTimelineStackView()
        configureCopyRawButton()
        configureLabel(errorLabel, textStyle: .callout, color: .systemRed)

        stackView.addArrangedSubview(loadingView)
        stackView.addArrangedSubview(timelineStackView)
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

    private func configureTimelineStackView() {
        timelineStackView.axis = .vertical
        timelineStackView.alignment = .fill
        timelineStackView.spacing = Metrics.sectionSpacing
        timelineStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        timelineStackView.setContentHuggingPriority(.required, for: .vertical)
        timelineStackView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func appendDisplayPartWithoutUpdatingVisibility(_ part: ChatResponseDisplayPart) {
        switch part {
        case let .reasoning(text):
            appendReasoningTimelinePart(text)
        case let .rawText(rawText):
            appendRawTextTimelinePart(rawText)
        case let .toolEvent(event):
            appendToolTimelineEvent(event)
        }
    }

    private func appendReasoningTimelinePart(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        ensureActiveThinkingSection().appendReasoning(text)
    }

    private func appendRawTextTimelinePart(_ rawTextDelta: String) {
        guard !rawTextDelta.isEmpty else {
            return
        }

        // Like VS Code's look-ahead completion for thinking parts, visible
        // assistant raw text is the boundary that ends the current thinking run.
        finishActiveThinkingSection(animated: true)
        rawText += rawTextDelta
        appendRawTextTimelineSegment(rawTextDelta)
    }

    private func appendToolTimelineEvent(_ event: ChatToolEvent) {
        switch event {
        case let .started(toolCall):
            let section = ensureActiveThinkingSection()
            toolSectionsByCallID[toolCall.id] = section
            let invocation = section.appendToolInvocation(
                callID: toolCall.id,
                displayName: toolCall.presentationName,
                state: .running
            )
            invocation.setDetail(toolCall.serializedArguments)
        case let .completed(toolCall, result):
            let section = toolSectionsByCallID[toolCall.id] ?? ensureActiveThinkingSection()
            toolSectionsByCallID[toolCall.id] = section
            let invocation = section.appendToolInvocation(
                callID: toolCall.id,
                displayName: toolCall.presentationName,
                state: .completed
            )
            invocation.setDetail(result)
        case let .failed(toolCall, message):
            let section = toolSectionsByCallID[toolCall.id] ?? ensureActiveThinkingSection()
            toolSectionsByCallID[toolCall.id] = section
            let invocation = section.appendToolInvocation(
                callID: toolCall.id,
                displayName: toolCall.presentationName,
                state: .failed(message: message)
            )
            invocation.setDetail(message)
        }
    }

    private func ensureActiveThinkingSection() -> ThinkingSectionView {
        if let activeThinkingSection {
            return activeThinkingSection
        }

        let section = ThinkingSectionView()
        timelineStackView.addArrangedSubview(section)
        timelineSegments.append(
            TimelineSegment(
                kind: .thinking,
                view: section,
                heightConstraint: nil
            )
        )
        activeThinkingSection = section
        return section
    }

    private func finishActiveThinkingSection(animated: Bool) {
        activeThinkingSection?.setThinking(false, animated: animated)
        activeThinkingSection = nil
    }

    private func finishAllThinkingSections(animated: Bool) {
        for segment in timelineSegments where segment.kind == .thinking {
            (segment.view as? ThinkingSectionView)?.setThinking(false, animated: animated)
        }
        activeThinkingSection = nil
    }

    private func appendRawTextTimelineSegment(_ rawTextDelta: String) {
        guard !rawTextDelta.isEmpty else {
            return
        }

        if let lastSegment = timelineSegments.last,
           lastSegment.kind == .rawText,
           let contentView = lastSegment.view as? StreamingContentView {
            contentView.appendContent(rawTextDelta)
            return
        }

        let contentView = makeResponseContentView()
        timelineStackView.addArrangedSubview(contentView)

        let heightConstraint = contentView.heightAnchor.constraint(equalToConstant: 0.0)
        heightConstraint.isActive = true
        timelineSegments.append(
            TimelineSegment(
                kind: .rawText,
                view: contentView,
                heightConstraint: heightConstraint
            )
        )
        contentView.appendContent(rawTextDelta)
    }

    private func appendFinishedRawTextTimelineSegment(_ rawText: String) {
        guard !rawText.isEmpty else {
            return
        }

        let contentView = makeResponseContentView()
        timelineStackView.addArrangedSubview(contentView)

        let heightConstraint = contentView.heightAnchor.constraint(equalToConstant: 0.0)
        heightConstraint.isActive = true
        timelineSegments.append(
            TimelineSegment(
                kind: .rawText,
                view: contentView,
                heightConstraint: heightConstraint
            )
        )
        contentView.setFinishedContent(rawText)
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
        finishActiveThinkingSection(animated: false)
        self.rawText += rawText
        appendFinishedRawTextTimelineSegment(rawText)
        updateVisibility()
    }

    private func finishRawTextTimelineSegments() {
        for segment in timelineSegments where segment.kind == .rawText {
            (segment.view as? StreamingContentView)?.finishStreamingContent()
        }
    }

    private func makeResponseContentView() -> StreamingContentView {
        let contentView = StreamingContentView()
        contentView.onNeedsHeightUpdate = { [weak self] in
            self?.updateContentViewHeights()
        }
        contentView.translatesAutoresizingMaskIntoConstraints = false
        return contentView
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

        timelineStackView.isHidden = timelineSegments.isEmpty
        let shouldShowCopyButton = shouldShowCopyRawButton
        let shouldAnimateCopyButtonAppearance = copyButtonContainerView.isHidden && shouldShowCopyButton
        copyButtonContainerView.isHidden = !shouldShowCopyButton
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        isHidden = !isLoading && timelineSegments.isEmpty && errorLabel.isHidden
        updateContentViewHeights()

        if shouldAnimateCopyButtonAppearance {
            animateCopyRawButtonAppearance()
        }
    }

    private var shouldShowCopyRawButton: Bool {
        isResponseFinished && !rawText.isEmpty
    }

    @objc private func copyRawText() {
        guard !rawText.isEmpty else {
            return
        }

        UIPasteboard.general.string = rawText
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

    private func updateContentViewHeightsIfNeeded() {
        let width = contentMeasurementWidth
        guard abs(width - lastMeasuredContentWidth) > 0.5 else {
            return
        }

        updateContentViewHeights()
    }

    private func updateContentViewHeights() {
        let width = contentMeasurementWidth
        guard width > 0.0 else {
            return
        }

        for segment in timelineSegments {
            guard let constraint = segment.heightConstraint else {
                continue
            }
            updateContentHeight(segment.view, constraint: constraint, width: width)
        }
        lastMeasuredContentWidth = width
        invalidateIntrinsicContentSize()
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

    private var contentMeasurementWidth: CGFloat {
        max(
            stackView.bounds.width,
            bounds.width - Metrics.horizontalInset * 2.0,
            (superview?.bounds.width ?? 0.0) - Metrics.horizontalInset * 2.0,
            1.0
        )
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
