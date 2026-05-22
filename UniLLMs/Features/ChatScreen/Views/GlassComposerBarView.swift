//
//  GlassComposerBarView.swift
//  UniLLMs
//
//  Implements the glass composer bar, including text input, send transitions, and stop-generation state.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class GlassComposerBarView: UIVisualEffectView, UITextViewDelegate {
    struct SendTransition {
        let text: String
        let backgroundGlobalFrame: CGRect
    }

    struct PendingAttachmentDisplay: Equatable {
        let id: UUID
        let image: UIImage?
        let filename: String
        let isFile: Bool
    }

    struct SelectedSystemPromptDisplay: Equatable {
        let id: UUID
        let title: String
    }

    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let spacing: CGFloat = 8.0
        static let fusionSpacing: CGFloat = 24.0
        static let capsuleHorizontalInset: CGFloat = 12.0
        static let capsuleComposingTrailingInset: CGFloat = 5.0
        static let capsuleVerticalInset: CGFloat = 5.0
        static let capsuleContentSpacing: CGFloat = 6.0
        static let textMinHeight: CGFloat = 32.0
        static let textMaxHeight: CGFloat = 118.0
        static let sendButtonSize: CGFloat = 34.0
        static let iconPointSize: CGFloat = 18.0
        static let transitionDuration: TimeInterval = 0.24
        static let attachmentChipSize: CGFloat = 110.0
        static let attachmentChipSpacing: CGFloat = 10.0
        static let attachmentPreviewVerticalPadding: CGFloat = 10.0
        static let attachmentPreviewBottomSpacing: CGFloat = 8.0
        static let systemPromptMinimumHeight: CGFloat = 44.0
        static let systemPromptVerticalInset: CGFloat = 8.0
        static let systemPromptBottomSpacing: CGFloat = 8.0
        static let systemPromptIconPointSize: CGFloat = 14.0
        static let systemPromptRemoveButtonSize: CGFloat = 44.0
        static let systemPromptPillHorizontalInset: CGFloat = 10.0
        static let systemPromptPillSpacing: CGFloat = 6.0
    }

    private let stackView = UIStackView()
    private let plusGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let waveformGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleContentStackView = UIStackView()
    private let plusButton = UIButton(type: .system)
    private let waveformButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let systemPromptContainerView = UIView()
    private let systemPromptPillView = UIView()
    private let systemPromptIconView = UIImageView()
    private let systemPromptTitleLabel = UILabel()
    private let systemPromptRemoveButton = UIButton(type: .system)
    private let attachmentPreviewContainerView = UIView()
    private let attachmentPreviewScrollView = UIScrollView()
    private let attachmentPreviewStackView = UIStackView()

    private var capsuleContentLeadingConstraint: NSLayoutConstraint!
    private var capsuleContentTrailingConstraint: NSLayoutConstraint!
    private var waveformWidthConstraint: NSLayoutConstraint!
    private var textHeightConstraint: NSLayoutConstraint!
    private var systemPromptHeightConstraint: NSLayoutConstraint!
    private var systemPromptBottomSpacingConstraint: NSLayoutConstraint!
    private var attachmentPreviewHeightConstraint: NSLayoutConstraint!
    private var attachmentPreviewBottomSpacingConstraint: NSLayoutConstraint!
    private var lastMeasuredTextWidth: CGFloat = 0.0
    private var isShowingSendControl = false
    private var isShowingStopControl = false
    private var isStreamingResponse = false
    private var pendingAttachments: [PendingAttachmentDisplay] = []
    private var selectedSystemPrompt: SelectedSystemPromptDisplay?

    var onSend: ((SendTransition) -> Void)?
    var onStop: (() -> Void)?
    var onPlusTap: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    var onRemoveAttachment: ((UUID) -> Void)?
    var onPreviewAttachment: ((UUID) -> Void)?
    var onRemoveSystemPrompt: (() -> Void)?
    var isSendingEnabled = true {
        didSet {
            updateSendControlAvailability()
        }
    }

    /// Source view used as the morph anchor for presentations triggered by the plus button.
    var plusSourceView: UIView {
        plusGlassView
    }

    private var containerGlassEffect: UIGlassContainerEffect? {
        effect as? UIGlassContainerEffect
    }

    init() {
        super.init(effect: GlassComposerBarView.makeContainerEffect())
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        effect = GlassComposerBarView.makeContainerEffect()
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = textView.bounds.width
        if abs(width - lastMeasuredTextWidth) > 0.5 {
            lastMeasuredTextWidth = width
            updateTextHeight(animated: false)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }

        updateFontsForCurrentContentSize()
        updateTextHeight(animated: false)
        updateSystemPromptPreviewHeight()
        onLayoutChange?()
    }

    func textViewDidChange(_ textView: UITextView) {
        let hasText = !textView.text.isEmpty
        placeholderLabel.isHidden = hasText
        updateInputMode(animated: true)
        updateTextHeight(animated: true)
    }

    func setStreamingResponseActive(_ isActive: Bool, animated: Bool) {
        guard isStreamingResponse != isActive else {
            return
        }

        isStreamingResponse = isActive
        updateWaveformButtonStyle()
        updateInputMode(animated: animated)
    }

    func setPendingAttachments(_ items: [PendingAttachmentDisplay]) {
        pendingAttachments = items
        rebuildAttachmentPreviewChips()
        let hasAttachments = !items.isEmpty

        attachmentPreviewContainerView.isHidden = !hasAttachments
        attachmentPreviewHeightConstraint.constant = hasAttachments
            ? Metrics.attachmentChipSize + Metrics.attachmentPreviewVerticalPadding * 2.0
            : 0.0
        updatePreviewSpacing()

        updateInputMode(animated: true)

        animatePreviewLayoutChange()
    }

    func setSelectedSystemPrompt(_ item: SelectedSystemPromptDisplay?) {
        selectedSystemPrompt = item
        systemPromptTitleLabel.text = item?.title
        systemPromptContainerView.isHidden = item == nil
        updateSystemPromptPreviewHeight()
        updatePreviewSpacing()
        animatePreviewLayoutChange()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureStackView()
        configurePlusButton()
        configureWaveformButton()
        configureCapsule()
        updateInputMode(animated: false)
    }

    private func configureStackView() {
        stackView.axis = .horizontal
        stackView.alignment = .bottom
        stackView.spacing = Metrics.spacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        stackView.addArrangedSubview(plusGlassView)
        stackView.addArrangedSubview(capsuleGlassView)
        stackView.addArrangedSubview(waveformGlassView)

        plusGlassView.translatesAutoresizingMaskIntoConstraints = false
        plusGlassView.cornerConfiguration = .capsule()
        plusGlassView.setContentHuggingPriority(.required, for: .horizontal)
        plusGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)

        capsuleGlassView.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.cornerConfiguration = .corners(
            radius: .fixed(Double(Metrics.controlHeight * 0.5))
        )
        capsuleGlassView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        capsuleGlassView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        waveformGlassView.translatesAutoresizingMaskIntoConstraints = false
        waveformGlassView.cornerConfiguration = .capsule()
        waveformGlassView.setContentHuggingPriority(.required, for: .horizontal)
        waveformGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)
        waveformWidthConstraint = waveformGlassView.widthAnchor.constraint(equalToConstant: Metrics.controlHeight)

        NSLayoutConstraint.activate([
            plusGlassView.widthAnchor.constraint(equalToConstant: Metrics.controlHeight),
            plusGlassView.heightAnchor.constraint(equalToConstant: Metrics.controlHeight),
            capsuleGlassView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            waveformWidthConstraint,
            waveformGlassView.heightAnchor.constraint(equalToConstant: Metrics.controlHeight)
        ])
    }

    private func configurePlusButton() {
        plusButton.tintColor = .label
        plusButton.setImage(
            UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .semibold)
            ),
            for: .normal
        )
        plusButton.accessibilityLabel = "Add"
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.addTarget(self, action: #selector(plusButtonPressed), for: .touchUpInside)
        plusGlassView.contentView.addSubview(plusButton)

        NSLayoutConstraint.activate([
            plusButton.topAnchor.constraint(equalTo: plusGlassView.contentView.topAnchor),
            plusButton.leadingAnchor.constraint(equalTo: plusGlassView.contentView.leadingAnchor),
            plusButton.trailingAnchor.constraint(equalTo: plusGlassView.contentView.trailingAnchor),
            plusButton.bottomAnchor.constraint(equalTo: plusGlassView.contentView.bottomAnchor)
        ])
    }

    private func configureWaveformButton() {
        waveformButton.tintColor = .label
        waveformButton.setImage(
            UIImage(
                systemName: "waveform",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .semibold)
            ),
            for: .normal
        )
        waveformButton.accessibilityLabel = "Waveform"
        waveformButton.translatesAutoresizingMaskIntoConstraints = false
        waveformButton.addTarget(self, action: #selector(waveformButtonPressed), for: .touchUpInside)
        waveformGlassView.contentView.addSubview(waveformButton)

        NSLayoutConstraint.activate([
            waveformButton.topAnchor.constraint(equalTo: waveformGlassView.contentView.topAnchor),
            waveformButton.leadingAnchor.constraint(equalTo: waveformGlassView.contentView.leadingAnchor),
            waveformButton.trailingAnchor.constraint(equalTo: waveformGlassView.contentView.trailingAnchor),
            waveformButton.bottomAnchor.constraint(equalTo: waveformGlassView.contentView.bottomAnchor)
        ])
    }

    private func configureCapsule() {
        configureTextView()
        configureSendButton()
        configureSystemPromptPreview()
        configureAttachmentPreview()

        capsuleContentStackView.axis = .horizontal
        capsuleContentStackView.alignment = .bottom
        capsuleContentStackView.spacing = Metrics.capsuleContentSpacing
        capsuleContentStackView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.contentView.addSubview(systemPromptContainerView)
        capsuleGlassView.contentView.addSubview(attachmentPreviewContainerView)
        capsuleGlassView.contentView.addSubview(capsuleContentStackView)
        capsuleContentStackView.addArrangedSubview(textView)
        capsuleGlassView.contentView.addSubview(sendButton)

        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Metrics.textMinHeight)
        systemPromptBottomSpacingConstraint = attachmentPreviewContainerView.topAnchor.constraint(
            equalTo: systemPromptContainerView.bottomAnchor,
            constant: 0.0
        )
        capsuleContentLeadingConstraint = capsuleContentStackView.leadingAnchor.constraint(
            equalTo: capsuleGlassView.contentView.leadingAnchor,
            constant: Metrics.capsuleHorizontalInset
        )
        capsuleContentTrailingConstraint = capsuleContentStackView.trailingAnchor.constraint(
            equalTo: capsuleGlassView.contentView.trailingAnchor,
            constant: -Metrics.capsuleHorizontalInset
        )
        attachmentPreviewBottomSpacingConstraint = capsuleContentStackView.topAnchor.constraint(
            equalTo: attachmentPreviewContainerView.bottomAnchor,
            constant: 0.0
        )

        NSLayoutConstraint.activate([
            systemPromptContainerView.topAnchor.constraint(
                equalTo: capsuleGlassView.contentView.topAnchor,
                constant: Metrics.capsuleVerticalInset
            ),
            systemPromptContainerView.leadingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.leadingAnchor,
                constant: Metrics.capsuleHorizontalInset
            ),
            systemPromptContainerView.trailingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.trailingAnchor,
                constant: -Metrics.capsuleHorizontalInset
            ),
            systemPromptHeightConstraint,
            systemPromptBottomSpacingConstraint,

            attachmentPreviewContainerView.leadingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.leadingAnchor,
                constant: Metrics.capsuleHorizontalInset
            ),
            attachmentPreviewContainerView.trailingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.trailingAnchor,
                constant: -Metrics.capsuleHorizontalInset
            ),

            attachmentPreviewBottomSpacingConstraint,
            capsuleContentLeadingConstraint,
            capsuleContentTrailingConstraint,
            capsuleContentStackView.bottomAnchor.constraint(
                equalTo: capsuleGlassView.contentView.bottomAnchor,
                constant: -Metrics.capsuleVerticalInset
            ),
            textHeightConstraint,

            sendButton.trailingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.trailingAnchor,
                constant: -Metrics.capsuleComposingTrailingInset
            ),
            sendButton.bottomAnchor.constraint(
                equalTo: capsuleGlassView.contentView.bottomAnchor,
                constant: -Metrics.capsuleVerticalInset
            ),
            sendButton.widthAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: Metrics.sendButtonSize)
        ])
    }

    private func configureSystemPromptPreview() {
        systemPromptContainerView.translatesAutoresizingMaskIntoConstraints = false
        systemPromptContainerView.clipsToBounds = true
        systemPromptContainerView.isHidden = true

        systemPromptPillView.translatesAutoresizingMaskIntoConstraints = false
        systemPromptPillView.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.72)
        systemPromptPillView.layer.cornerRadius = Metrics.systemPromptMinimumHeight * 0.5
        systemPromptPillView.layer.cornerCurve = .continuous
        systemPromptPillView.clipsToBounds = true
        systemPromptContainerView.addSubview(systemPromptPillView)

        systemPromptIconView.translatesAutoresizingMaskIntoConstraints = false
        systemPromptIconView.contentMode = .scaleAspectFit
        systemPromptIconView.tintColor = .secondaryLabel
        systemPromptIconView.image = UIImage(
            systemName: "text.quote",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Metrics.systemPromptIconPointSize,
                weight: .semibold
            )
        )
        systemPromptIconView.setContentHuggingPriority(.required, for: .horizontal)
        systemPromptIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        systemPromptPillView.addSubview(systemPromptIconView)

        systemPromptTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        systemPromptTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        systemPromptTitleLabel.adjustsFontForContentSizeCategory = true
        systemPromptTitleLabel.textColor = .label
        systemPromptTitleLabel.lineBreakMode = .byTruncatingMiddle
        systemPromptTitleLabel.numberOfLines = 1
        systemPromptTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        systemPromptPillView.addSubview(systemPromptTitleLabel)

        var removeConfig = UIButton.Configuration.plain()
        removeConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10.0, weight: .bold)
        )
        removeConfig.baseForegroundColor = .secondaryLabel
        removeConfig.contentInsets = .zero
        systemPromptRemoveButton.configuration = removeConfig
        systemPromptRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        systemPromptRemoveButton.accessibilityLabel = "Remove system prompt"
        systemPromptRemoveButton.setContentHuggingPriority(.required, for: .horizontal)
        systemPromptRemoveButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        systemPromptRemoveButton.addTarget(
            self,
            action: #selector(removeSystemPromptButtonPressed),
            for: .touchUpInside
        )
        systemPromptPillView.addSubview(systemPromptRemoveButton)

        systemPromptHeightConstraint = systemPromptContainerView.heightAnchor.constraint(equalToConstant: 0.0)

        NSLayoutConstraint.activate([
            systemPromptPillView.topAnchor.constraint(equalTo: systemPromptContainerView.topAnchor),
            systemPromptPillView.leadingAnchor.constraint(equalTo: systemPromptContainerView.leadingAnchor),
            systemPromptPillView.trailingAnchor.constraint(lessThanOrEqualTo: systemPromptContainerView.trailingAnchor),
            systemPromptPillView.bottomAnchor.constraint(equalTo: systemPromptContainerView.bottomAnchor),

            systemPromptIconView.leadingAnchor.constraint(
                equalTo: systemPromptPillView.leadingAnchor,
                constant: Metrics.systemPromptPillHorizontalInset
            ),
            systemPromptIconView.centerYAnchor.constraint(equalTo: systemPromptPillView.centerYAnchor),

            systemPromptTitleLabel.leadingAnchor.constraint(
                equalTo: systemPromptIconView.trailingAnchor,
                constant: Metrics.systemPromptPillSpacing
            ),
            systemPromptTitleLabel.centerYAnchor.constraint(equalTo: systemPromptPillView.centerYAnchor),

            systemPromptRemoveButton.leadingAnchor.constraint(
                equalTo: systemPromptTitleLabel.trailingAnchor,
                constant: Metrics.systemPromptPillSpacing
            ),
            systemPromptRemoveButton.trailingAnchor.constraint(
                equalTo: systemPromptPillView.trailingAnchor,
                constant: -Metrics.systemPromptPillHorizontalInset
            ),
            systemPromptRemoveButton.centerYAnchor.constraint(equalTo: systemPromptPillView.centerYAnchor),
            systemPromptRemoveButton.widthAnchor.constraint(equalToConstant: Metrics.systemPromptRemoveButtonSize),
            systemPromptRemoveButton.heightAnchor.constraint(equalToConstant: Metrics.systemPromptRemoveButtonSize)
        ])
    }

    private func configureAttachmentPreview() {
        attachmentPreviewContainerView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewContainerView.clipsToBounds = true
        attachmentPreviewContainerView.isHidden = true

        attachmentPreviewScrollView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewScrollView.showsHorizontalScrollIndicator = false
        attachmentPreviewScrollView.showsVerticalScrollIndicator = false
        attachmentPreviewScrollView.alwaysBounceHorizontal = true
        attachmentPreviewScrollView.contentInset = .zero
        attachmentPreviewContainerView.addSubview(attachmentPreviewScrollView)

        attachmentPreviewStackView.axis = .horizontal
        attachmentPreviewStackView.alignment = .center
        attachmentPreviewStackView.spacing = Metrics.attachmentChipSpacing
        attachmentPreviewStackView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewScrollView.addSubview(attachmentPreviewStackView)

        attachmentPreviewHeightConstraint = attachmentPreviewContainerView.heightAnchor.constraint(equalToConstant: 0.0)
        attachmentPreviewHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            attachmentPreviewScrollView.topAnchor.constraint(equalTo: attachmentPreviewContainerView.topAnchor),
            attachmentPreviewScrollView.leadingAnchor.constraint(equalTo: attachmentPreviewContainerView.leadingAnchor),
            attachmentPreviewScrollView.trailingAnchor.constraint(equalTo: attachmentPreviewContainerView.trailingAnchor),
            attachmentPreviewScrollView.bottomAnchor.constraint(equalTo: attachmentPreviewContainerView.bottomAnchor),

            attachmentPreviewStackView.topAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.topAnchor),
            attachmentPreviewStackView.leadingAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.leadingAnchor),
            attachmentPreviewStackView.trailingAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.trailingAnchor),
            attachmentPreviewStackView.bottomAnchor.constraint(equalTo: attachmentPreviewScrollView.contentLayoutGuide.bottomAnchor),
            attachmentPreviewStackView.heightAnchor.constraint(equalTo: attachmentPreviewScrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func configureTextView() {
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.returnKeyType = .default
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 5.5, left: 0.0, bottom: 4.5, right: 0.0)
        textView.textContainer.lineFragmentPadding = 0.0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        placeholderLabel.text = "Message"
        placeholderLabel.font = textView.font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top)
        ])
    }

    private func configureSendButton() {
        var configuration = UIButton.Configuration.prominentClearGlass()
        configuration.image = UIImage(
            systemName: "arrow.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .bold)
        )
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        sendButton.configuration = configuration
        sendButton.accessibilityLabel = "Send"
        sendButton.addTarget(self, action: #selector(sendButtonPressed), for: .touchUpInside)
    }

    @objc private func waveformButtonPressed() {
        guard isStreamingResponse else {
            return
        }

        onStop?()
    }

    @objc private func plusButtonPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPlusTap?()
    }

    @objc private func removeSystemPromptButtonPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onRemoveSystemPrompt?()
    }

    @objc private func sendButtonPressed() {
        guard isSendingEnabled else {
            return
        }

        let messageText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty || !pendingAttachments.isEmpty else {
            return
        }

        layoutIfNeeded()

        let transition = SendTransition(
            text: messageText,
            backgroundGlobalFrame: capsuleGlassView.convert(capsuleGlassView.bounds, to: nil)
        )

        textView.text = ""
        placeholderLabel.isHidden = false
        updateInputMode(animated: true)
        updateTextHeight(animated: true)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSend?(transition)
    }

    private func updateInputMode(animated: Bool) {
        let hasText = !textView.text.isEmpty
        let hasContent = hasText || !pendingAttachments.isEmpty
        let shouldShowStopControl = isStreamingResponse
        let shouldShowSendControl = hasContent && !shouldShowStopControl
        let shouldShowWaveformControl = !shouldShowSendControl
        let stateChanged = shouldShowSendControl != isShowingSendControl
            || shouldShowStopControl != isShowingStopControl
        isShowingSendControl = shouldShowSendControl
        isShowingStopControl = shouldShowStopControl

        guard stateChanged || !animated else {
            return
        }

        let applyTargetState = { [self] in
            self.capsuleContentLeadingConstraint.constant = Metrics.capsuleHorizontalInset
            self.capsuleContentTrailingConstraint.constant = shouldShowSendControl
                ? -(Metrics.capsuleComposingTrailingInset + Metrics.sendButtonSize + Metrics.capsuleContentSpacing)
                : -Metrics.capsuleHorizontalInset
            self.waveformWidthConstraint.constant = shouldShowWaveformControl ? Metrics.controlHeight : 0.0
            self.stackView.setCustomSpacing(shouldShowWaveformControl ? Metrics.spacing : 0.0, after: self.capsuleGlassView)
            self.sendButton.alpha = shouldShowSendControl ? 1.0 : 0.0
            self.waveformGlassView.alpha = shouldShowWaveformControl ? 1.0 : 0.0
            self.superview?.layoutIfNeeded()
            self.layoutIfNeeded()
        }

        if animated {
            sendButton.isHidden = false
            waveformGlassView.isHidden = false
            updateWaveformButtonStyle()
            updateSendControlAvailability()
            updateWaveformControlAvailability()
            if shouldShowSendControl {
                sendButton.alpha = 0.0
            }

            containerGlassEffect?.spacing = Metrics.fusionSpacing
            UIView.animate(
                withDuration: Metrics.transitionDuration,
                delay: 0.0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: {
                    applyTargetState()
                },
                completion: { _ in
                    guard self.isShowingSendControl == shouldShowSendControl,
                          self.isShowingStopControl == shouldShowStopControl else {
                        return
                    }

                    self.containerGlassEffect?.spacing = Metrics.spacing
                    self.sendButton.isHidden = !shouldShowSendControl
                    self.waveformGlassView.isHidden = !shouldShowWaveformControl
                    self.updateSendControlAvailability()
                    self.updateWaveformControlAvailability()
                }
            )
        } else {
            containerGlassEffect?.spacing = Metrics.spacing
            updateWaveformButtonStyle()
            applyTargetState()
            sendButton.isHidden = !shouldShowSendControl
            updateSendControlAvailability()
            waveformGlassView.isHidden = !shouldShowWaveformControl
            updateWaveformControlAvailability()
        }
    }

    private func updateSendControlAvailability() {
        sendButton.isEnabled = isSendingEnabled
        sendButton.isUserInteractionEnabled = isShowingSendControl && isSendingEnabled
    }

    private func updateWaveformControlAvailability() {
        waveformButton.isUserInteractionEnabled = isShowingStopControl
    }

    private func updateWaveformButtonStyle() {
        if isStreamingResponse {
            waveformButton.configuration = nil
            waveformGlassView.effect = GlassComposerBarView.makeGlassEffect(tintColor: .systemRed)
            waveformButton.tintColor = .white
            waveformButton.setImage(
                UIImage(
                    systemName: "stop.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.0, weight: .bold)
                ),
                for: .normal
            )
            waveformButton.accessibilityLabel = "Stop generating"
        } else {
            waveformButton.configuration = nil
            waveformGlassView.effect = GlassComposerBarView.makeGlassEffect()
            waveformButton.tintColor = .label
            waveformButton.setImage(
                UIImage(
                    systemName: "waveform",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .semibold)
                ),
                for: .normal
            )
            waveformButton.accessibilityLabel = "Waveform"
        }
    }

    private func updateFontsForCurrentContentSize() {
        textView.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.font = textView.font
        systemPromptTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
    }

    private func updateTextHeight(animated: Bool) {
        let fittingWidth = max(textView.bounds.width, 1.0)
        let fittingSize = textView.sizeThatFits(
            CGSize(width: fittingWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        let targetHeight = min(max(ceil(fittingSize.height), Metrics.textMinHeight), Metrics.textMaxHeight)

        textView.isScrollEnabled = fittingSize.height > Metrics.textMaxHeight

        guard abs(textHeightConstraint.constant - targetHeight) > 0.5 else {
            return
        }

        textHeightConstraint.constant = targetHeight

        let layoutChanges = {
            self.superview?.layoutIfNeeded()
            self.onLayoutChange?()
            return
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0.0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: layoutChanges
            )
        } else {
            layoutChanges()
        }
    }

    private static func makeContainerEffect() -> UIGlassContainerEffect {
        let effect = UIGlassContainerEffect()
        effect.spacing = Metrics.spacing
        return effect
    }

    private static func makeGlassEffect(tintColor: UIColor? = nil) -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        effect.tintColor = tintColor
        return effect
    }

    private func rebuildAttachmentPreviewChips() {
        attachmentPreviewStackView.arrangedSubviews.forEach { view in
            attachmentPreviewStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for item in pendingAttachments {
            let chip = ComposerAttachmentChipView(item: item)
            chip.onRemove = { [weak self] id in
                self?.onRemoveAttachment?(id)
            }
            chip.onPreview = { [weak self] id in
                self?.onPreviewAttachment?(id)
            }
            attachmentPreviewStackView.addArrangedSubview(chip)
            chip.widthAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
            chip.heightAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
        }
    }

    private func updatePreviewSpacing() {
        let hasSystemPrompt = selectedSystemPrompt != nil
        let hasAttachments = !pendingAttachments.isEmpty
        systemPromptBottomSpacingConstraint.constant = hasSystemPrompt && hasAttachments
            ? Metrics.systemPromptBottomSpacing
            : 0.0
        attachmentPreviewBottomSpacingConstraint.constant = hasSystemPrompt || hasAttachments
            ? Metrics.attachmentPreviewBottomSpacing
            : 0.0
    }

    private func updateSystemPromptPreviewHeight() {
        let height = selectedSystemPrompt == nil ? 0.0 : systemPromptPreviewHeight
        systemPromptHeightConstraint.constant = height
        systemPromptPillView.layer.cornerRadius = height * 0.5
    }

    private var systemPromptPreviewHeight: CGFloat {
        max(
            Metrics.systemPromptMinimumHeight,
            ceil(systemPromptTitleLabel.font.lineHeight + Metrics.systemPromptVerticalInset * 2.0)
        )
    }

    private func animatePreviewLayoutChange() {
        UIView.animate(
            withDuration: 0.2,
            delay: 0.0,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: {
                self.superview?.layoutIfNeeded()
                self.layoutIfNeeded()
                self.onLayoutChange?()
            }
        )
    }
}

private final class ComposerAttachmentChipView: UIView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 16.0
        static let removeButtonSize: CGFloat = 24.0
        static let removeButtonInset: CGFloat = 5.0
        static let removeIconPointSize: CGFloat = 10.0
        static let fileIconPointSize: CGFloat = 30.0
        static let filenameFontSize: CGFloat = 11.0
        static let filenameBottomInset: CGFloat = 7.0
        static let filenameHorizontalInset: CGFloat = 6.0
    }

    private let backgroundView = UIView()
    private let imageView = UIImageView()
    private let fileIconView = UIImageView()
    private let filenameLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    private let itemID: UUID

    var onRemove: ((UUID) -> Void)?
    var onPreview: ((UUID) -> Void)?

    init(item: GlassComposerBarView.PendingAttachmentDisplay) {
        itemID = item.id
        super.init(frame: .zero)
        configure(item: item)
    }

    required init?(coder: NSCoder) {
        itemID = UUID()
        super.init(coder: coder)
    }

    private func configure(item: GlassComposerBarView.PendingAttachmentDisplay) {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = Metrics.cornerRadius
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.clipsToBounds = true
        backgroundView.backgroundColor = UIColor.secondarySystemFill
        backgroundView.isUserInteractionEnabled = true
        backgroundView.isAccessibilityElement = true
        backgroundView.accessibilityLabel = item.filename
        backgroundView.accessibilityHint = "Opens a preview"
        backgroundView.accessibilityTraits = .button
        backgroundView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(previewTapped))
        )
        addSubview(backgroundView)

        if item.isFile {
            fileIconView.translatesAutoresizingMaskIntoConstraints = false
            fileIconView.contentMode = .scaleAspectFit
            fileIconView.tintColor = .label
            fileIconView.image = UIImage(
                systemName: "doc.text.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: Metrics.fileIconPointSize,
                    weight: .semibold
                )
            )
            backgroundView.addSubview(fileIconView)

            filenameLabel.translatesAutoresizingMaskIntoConstraints = false
            filenameLabel.text = item.filename
            filenameLabel.font = .systemFont(ofSize: Metrics.filenameFontSize, weight: .medium)
            filenameLabel.textColor = .label
            filenameLabel.textAlignment = .center
            filenameLabel.numberOfLines = 1
            filenameLabel.lineBreakMode = .byTruncatingMiddle
            backgroundView.addSubview(filenameLabel)
        } else {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.image = item.image
            backgroundView.addSubview(imageView)
        }

        var removeConfig = UIButton.Configuration.filled()
        removeConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.removeIconPointSize, weight: .bold)
        )
        removeConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.72)
        removeConfig.baseForegroundColor = .white
        removeConfig.cornerStyle = .capsule
        removeConfig.contentInsets = .zero
        removeButton.configuration = removeConfig
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.accessibilityLabel = "Remove attachment"
        removeButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.onRemove?(self.itemID)
            },
            for: .touchUpInside
        )
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            removeButton.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.removeButtonInset),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.removeButtonInset),
            removeButton.widthAnchor.constraint(equalToConstant: Metrics.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Metrics.removeButtonSize)
        ])

        if item.isFile {
            NSLayoutConstraint.activate([
                fileIconView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
                fileIconView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor, constant: -7.0),

                filenameLabel.leadingAnchor.constraint(
                    equalTo: backgroundView.leadingAnchor,
                    constant: Metrics.filenameHorizontalInset
                ),
                filenameLabel.trailingAnchor.constraint(
                    equalTo: backgroundView.trailingAnchor,
                    constant: -Metrics.filenameHorizontalInset
                ),
                filenameLabel.bottomAnchor.constraint(
                    equalTo: backgroundView.bottomAnchor,
                    constant: -Metrics.filenameBottomInset
                )
            ])
        } else {
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
            ])
        }
    }

    @objc private func previewTapped() {
        onPreview?(itemID)
    }
}
