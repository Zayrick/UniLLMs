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
        static let copyIconPointSize: CGFloat = 14.0
        static let copyAppearTranslationY: CGFloat = -8.0
        static let copyAppearAnimationDuration: TimeInterval = 0.46
        static let copyAppearAnimationDampingRatio: CGFloat = 0.88
    }

    private enum TimelineSegmentKind {
        case toolStatus
        case reasoning
        case content
    }

    private struct TimelineSegment {
        var kind: TimelineSegmentKind
        var view: UIView
        var heightConstraint: NSLayoutConstraint
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
    private var isResponseFinished = false
    private var rawContentMarkdown = ""
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
        isResponseFinished = false
        errorLabel.text = nil

        if !reasoningDelta.isEmpty {
            appendPlainTimelineSegment(
                kind: .reasoning,
                text: reasoningDelta,
                attributes: reasoningAttributes
            )
        }
        if !contentDelta.isEmpty {
            rawContentMarkdown += contentDelta
            appendContentTimelineSegment(contentDelta)
        }

        updateVisibility()
    }

    func append(toolStatus statusDelta: String) {
        guard !statusDelta.isEmpty else {
            return
        }

        isLoading = false
        errorLabel.text = nil
        appendPlainTimelineSegment(
            kind: .toolStatus,
            text: statusDelta,
            attributes: toolStatusAttributes
        )
        updateVisibility()
    }

    func setError(_ message: String) {
        isLoading = false
        isResponseFinished = true
        finishContentTimelineSegments()
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
        finishContentTimelineSegments()
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

    private func configureTimelineStackView() {
        timelineStackView.axis = .vertical
        timelineStackView.alignment = .fill
        timelineStackView.spacing = Metrics.sectionSpacing
        timelineStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        timelineStackView.setContentHuggingPriority(.required, for: .vertical)
        timelineStackView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func appendPlainTimelineSegment(
        kind: TimelineSegmentKind,
        text: String,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard !text.isEmpty else {
            return
        }

        if let lastSegment = timelineSegments.last,
           lastSegment.kind == kind,
           let textView = lastSegment.view as? StreamingTextView {
            textView.append(text, attributes: attributes)
            return
        }

        let textView = StreamingTextView()
        configurePlainTextView(textView, textStyle: .callout, color: .secondaryLabel)
        timelineStackView.addArrangedSubview(textView)

        let heightConstraint = textView.heightAnchor.constraint(equalToConstant: 0.0)
        heightConstraint.isActive = true
        timelineSegments.append(
            TimelineSegment(
                kind: kind,
                view: textView,
                heightConstraint: heightConstraint
            )
        )
        textView.append(text, attributes: attributes)
    }

    private func appendContentTimelineSegment(_ markdown: String) {
        guard !markdown.isEmpty else {
            return
        }

        if let lastSegment = timelineSegments.last,
           lastSegment.kind == .content,
           let markdownView = lastSegment.view as? StreamingMarkdownView {
            markdownView.appendMarkdown(markdown)
            return
        }

        let markdownView = makeContentMarkdownView()
        timelineStackView.addArrangedSubview(markdownView)

        let heightConstraint = markdownView.heightAnchor.constraint(equalToConstant: 0.0)
        heightConstraint.isActive = true
        timelineSegments.append(
            TimelineSegment(
                kind: .content,
                view: markdownView,
                heightConstraint: heightConstraint
            )
        )
        markdownView.appendMarkdown(markdown)
    }

    private func finishContentTimelineSegments() {
        for segment in timelineSegments where segment.kind == .content {
            (segment.view as? StreamingMarkdownView)?.finishStreamingContent()
        }
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

        timelineStackView.isHidden = timelineSegments.isEmpty
        let shouldShowCopyButton = shouldShowCopyMarkdownButton
        let shouldAnimateCopyButtonAppearance = copyButtonContainerView.isHidden && shouldShowCopyButton
        copyButtonContainerView.isHidden = !shouldShowCopyButton
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        isHidden = !isLoading && timelineSegments.isEmpty && errorLabel.isHidden
        updateTextViewHeights()

        if shouldAnimateCopyButtonAppearance {
            animateCopyMarkdownButtonAppearance()
        }
    }

    private var shouldShowCopyMarkdownButton: Bool {
        isResponseFinished && !rawContentMarkdown.isEmpty
    }

    @objc private func copyRawMarkdown() {
        guard !rawContentMarkdown.isEmpty else {
            return
        }

        UIPasteboard.general.string = rawContentMarkdown
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
            if let textView = segment.view as? UITextView {
                updateTextViewHeight(textView, constraint: segment.heightConstraint, width: width)
            } else {
                updateContentHeight(segment.view, constraint: segment.heightConstraint, width: width)
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

    private var reasoningAttributes: [NSAttributedString.Key: Any] {
        let font = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traitCollection)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Self.systemLineSpacing(for: font)
        paragraphStyle.paragraphSpacing = Self.systemParagraphSpacing(for: font)

        return [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: UIColor.secondaryLabel,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]
    }

    private var toolStatusAttributes: [NSAttributedString.Key: Any] {
        let font = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traitCollection)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Self.systemLineSpacing(for: font)
        paragraphStyle.paragraphSpacing = Self.systemParagraphSpacing(for: font)

        return [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: UIColor.secondaryLabel,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]
    }

    private static func systemParagraphSpacing(for font: UIFont) -> CGFloat {
        ceil(max(font.leading, font.lineHeight - font.pointSize))
    }

    private static func systemLineSpacing(for font: UIFont) -> CGFloat {
        ceil(max(font.leading, font.lineHeight - font.pointSize))
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

    private final class CopyMarkdownButton: UIControl {
        private enum SymbolName {
            static let copy = "doc.on.doc"
            static let copied = "checkmark"
        }

        private let imageView = UIImageView()
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

        override var isHighlighted: Bool {
            didSet {
                imageView.alpha = isHighlighted ? 0.45 : 1.0
            }
        }

        func showCopiedFeedback() {
            guard !isShowingFeedback else {
                return
            }

            isShowingFeedback = true
            isUserInteractionEnabled = false
            accessibilityLabel = "Copied"

            setSymbol(named: SymbolName.copied, animated: true) { [weak self] in
                guard let self else {
                    return
                }

                self.setSymbol(named: SymbolName.copy, animated: true) { [weak self] in
                    self?.accessibilityLabel = "Copy Markdown"
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

            imageView.addSymbolEffect(
                .appear.up.wholeSymbol,
                options: .nonRepeating,
                animated: true
            )
        }

        private func configure() {
            backgroundColor = .clear
            isOpaque = false
            isAccessibilityElement = true
            accessibilityLabel = "Copy Markdown"
            accessibilityTraits = .button
            tintColor = .tertiaryLabel

            imageView.tintColor = tintColor
            imageView.contentMode = .center
            imageView.isUserInteractionEnabled = false
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

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
                  !UIAccessibility.isReduceMotionEnabled else {
                imageView.image = image
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

                if !context.isFinished {
                    self.imageView.image = image
                }
                completion?()
            }
        }
    }
}
