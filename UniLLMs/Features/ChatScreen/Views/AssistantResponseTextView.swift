//
//  AssistantResponseTextView.swift
//  UniLLMs
//
//  Displays assistant streaming content, reasoning text, loading state, and error messages.
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

    private struct TimelineSegment {
        var view: UIView
        var heightConstraint: NSLayoutConstraint?
    }

    private let stackView = UIStackView()
    private let loadingView = UIStackView()
    private let loadingIndicatorView = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let timelineStackView = UIStackView()
    private let copyButtonContainerView = UIView()
    private let copyMarkdownButton = CopyMarkdownButton(
        symbolConfiguration: UIImage.SymbolConfiguration(
            pointSize: Metrics.copyIconPointSize,
            weight: .medium
        )
    )
    private let errorLabel = UILabel()
    private var timelineSegments: [TimelineSegment] = []
    private var timelineState = ChatAssistantResponseTimelinePresentationState()
    private var thinkingSectionsBySegmentID: [
        ChatAssistantResponseTimelinePresentationState.SegmentID: ThinkingSectionView
    ] = [:]
    private var contentViewsBySegmentID: [
        ChatAssistantResponseTimelinePresentationState.SegmentID: StreamingMarkdownView
    ] = [:]
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

        appendDisplayParts(
            ChatResponseDelta(
                content: contentDelta,
                reasoning: reasoningDelta
            ).displayParts
        )
    }

    func appendDisplayPart(_ part: ChatResponseDisplayPart) {
        appendDisplayParts([part])
    }

    func appendToolEvent(_ event: ChatToolEvent) {
        appendDisplayParts([.toolEvent(event)])
    }

    private func appendDisplayParts(_ parts: [ChatResponseDisplayPart]) {
        let actions = timelineState.appendDisplayParts(parts)
        guard !actions.isEmpty else {
            return
        }

        isLoading = false
        errorLabel.text = nil

        applyTimelineActions(actions)
        updateVisibility()
    }

    func setError(_ message: String) {
        isLoading = false
        applyTimelineActions(timelineState.setError())
        errorLabel.text = message
        updateVisibility()
    }

    func showLoadingIfNeeded() {
        guard timelineState.isEmpty,
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
        applyTimelineActions(timelineState.finishStreamingContent())
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
        configureCopyMarkdownButton()
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

    private func appendThinkingSegment(
        id segmentID: ChatAssistantResponseTimelinePresentationState.SegmentID
    ) {
        let section = ThinkingSectionView()
        timelineStackView.addArrangedSubview(section)
        timelineSegments.append(
            TimelineSegment(
                view: section,
                heightConstraint: nil
            )
        )
        thinkingSectionsBySegmentID[segmentID] = section
    }

    private func appendContentTimelineSegment(
        id segmentID: ChatAssistantResponseTimelinePresentationState.SegmentID
    ) {
        let markdownView = makeContentMarkdownView()
        timelineStackView.addArrangedSubview(markdownView)

        let heightConstraint = markdownView.heightAnchor.constraint(equalToConstant: 0.0)
        heightConstraint.isActive = true
        timelineSegments.append(
            TimelineSegment(
                view: markdownView,
                heightConstraint: heightConstraint
            )
        )
        contentViewsBySegmentID[segmentID] = markdownView
    }

    private func applyTimelineActions(
        _ actions: [ChatAssistantResponseTimelinePresentationState.Action]
    ) {
        for action in actions {
            applyTimelineAction(action)
        }
    }

    private func applyTimelineAction(
        _ action: ChatAssistantResponseTimelinePresentationState.Action
    ) {
        switch action {
        case let .createThinkingSegment(segmentID):
            appendThinkingSegment(id: segmentID)
        case let .appendReasoning(segmentID, text):
            thinkingSection(for: segmentID)?.appendReasoning(text)
        case let .finishThinkingSegment(segmentID, animated):
            thinkingSection(for: segmentID)?.setThinking(false, animated: animated)
        case let .createContentSegment(segmentID):
            appendContentTimelineSegment(id: segmentID)
        case let .appendContentMarkdown(segmentID, markdown):
            contentView(for: segmentID)?.appendMarkdown(markdown)
        case let .setFinishedContentMarkdown(segmentID, markdown):
            contentView(for: segmentID)?.setFinishedMarkdown(markdown)
        case let .appendToolInvocation(segmentID, invocation):
            appendToolInvocation(invocation, toSegment: segmentID)
        case let .finishContentSegment(segmentID):
            contentView(for: segmentID)?.finishStreamingContent()
        }
    }

    private func appendToolInvocation(
        _ invocation: ChatAssistantResponseTimelinePresentationState.ToolInvocationPresentation,
        toSegment segmentID: ChatAssistantResponseTimelinePresentationState.SegmentID
    ) {
        guard let section = thinkingSection(for: segmentID) else {
            return
        }

        let invocationView = section.appendToolInvocation(
            callID: invocation.callID,
            displayName: invocation.displayName,
            state: invocation.state.toolInvocationViewState
        )
        invocationView.setDetail(invocation.detail)
    }

    private func thinkingSection(
        for segmentID: ChatAssistantResponseTimelinePresentationState.SegmentID
    ) -> ThinkingSectionView? {
        guard let section = thinkingSectionsBySegmentID[segmentID] else {
            assertionFailure("Missing thinking section for \(segmentID)")
            return nil
        }
        return section
    }

    private func contentView(
        for segmentID: ChatAssistantResponseTimelinePresentationState.SegmentID
    ) -> StreamingMarkdownView? {
        guard let contentView = contentViewsBySegmentID[segmentID] else {
            assertionFailure("Missing content segment for \(segmentID)")
            return nil
        }
        return contentView
    }

    func appendStoredReasoning(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        appendDisplayParts([.reasoning(text)])
    }

    func appendStoredContentMarkdown(_ markdown: String) {
        let actions = timelineState.appendStoredContentMarkdown(markdown)
        guard !actions.isEmpty else {
            return
        }

        isLoading = false
        errorLabel.text = nil
        applyTimelineActions(actions)
        updateVisibility()
    }

    private func makeContentMarkdownView() -> StreamingMarkdownView {
        let contentMarkdownView = StreamingMarkdownView()
        contentMarkdownView.backgroundColor = .clear
        contentMarkdownView.isOpaque = false
        contentMarkdownView.onNeedsHeightUpdate = { [weak self] in
            self?.updateTextViewHeights()
        }
        contentMarkdownView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentMarkdownView.setContentHuggingPriority(.required, for: .vertical)
        contentMarkdownView.translatesAutoresizingMaskIntoConstraints = false
        return contentMarkdownView
    }

    private func configureCopyMarkdownButton() {
        copyButtonContainerView.backgroundColor = .clear
        copyButtonContainerView.isOpaque = false
        copyButtonContainerView.setContentCompressionResistancePriority(.required, for: .vertical)
        copyButtonContainerView.setContentHuggingPriority(.required, for: .vertical)
        copyButtonContainerView.translatesAutoresizingMaskIntoConstraints = false

        copyMarkdownButton.translatesAutoresizingMaskIntoConstraints = false
        copyMarkdownButton.addTarget(
            self,
            action: #selector(copyRawMarkdown),
            for: .touchUpInside
        )
        copyButtonContainerView.addSubview(copyMarkdownButton)

        NSLayoutConstraint.activate([
            copyMarkdownButton.topAnchor.constraint(equalTo: copyButtonContainerView.topAnchor),
            copyMarkdownButton.leadingAnchor.constraint(equalTo: copyButtonContainerView.leadingAnchor),
            copyMarkdownButton.bottomAnchor.constraint(equalTo: copyButtonContainerView.bottomAnchor),
            copyMarkdownButton.trailingAnchor.constraint(
                lessThanOrEqualTo: copyButtonContainerView.trailingAnchor
            ),
            copyMarkdownButton.widthAnchor.constraint(equalToConstant: Metrics.copyButtonSideLength),
            copyMarkdownButton.heightAnchor.constraint(equalToConstant: Metrics.copyButtonSideLength)
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

        timelineStackView.isHidden = timelineState.isEmpty
        let shouldShowCopyButton = shouldShowCopyMarkdownButton
        let shouldAnimateCopyButtonAppearance = copyButtonContainerView.isHidden && shouldShowCopyButton
        copyButtonContainerView.isHidden = !shouldShowCopyButton
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        isHidden = !isLoading && timelineState.isEmpty && errorLabel.isHidden
        updateTextViewHeights()

        if shouldAnimateCopyButtonAppearance {
            animateCopyMarkdownButtonAppearance()
        }
    }

    private var shouldShowCopyMarkdownButton: Bool {
        timelineState.shouldShowCopyMarkdownButton
    }

    @objc private func copyRawMarkdown() {
        guard !timelineState.rawContentMarkdown.isEmpty else {
            return
        }

        UIPasteboard.general.string = timelineState.rawContentMarkdown
        copyMarkdownButton.showCopiedFeedback()
    }

    private func animateCopyMarkdownButtonAppearance() {
        copyMarkdownButton.playAppearAnimation()

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

        for segment in timelineSegments {
            guard let constraint = segment.heightConstraint else {
                continue
            }
            if let textView = segment.view as? UITextView {
                updateTextViewHeight(textView, constraint: constraint, width: width)
            } else {
                updateContentHeight(segment.view, constraint: constraint, width: width)
            }
        }
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

    private final class CopyMarkdownButton: UIButton {
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
                    self?.accessibilityLabel = String(localized: .assistantCopyMarkdown)
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
            accessibilityLabel = String(localized: .assistantCopyMarkdown)
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

private extension ChatAssistantResponseTimelinePresentationState.ToolInvocationState {
    var toolInvocationViewState: ToolInvocationView.State {
        switch self {
        case .running:
            return .running
        case .completed:
            return .completed
        case let .failed(message):
            return .failed(message: message)
        }
    }
}
