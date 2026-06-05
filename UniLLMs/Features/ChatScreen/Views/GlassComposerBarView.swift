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
        static let capsuleHorizontalInset: CGFloat = 7.0
        static let inputTextLeadingInset: CGFloat = 5.0
        static let capsulePreviewTopInset: CGFloat = 7.0
        static let capsuleVerticalInset: CGFloat = 5.0
        static let capsulePreviewGap: CGFloat = 7.0
        static let capsuleContentSpacing: CGFloat = 6.0
        static let textMinHeight: CGFloat = 32.0
        static let textMaxHeight: CGFloat = 118.0
        static let sendButtonSize: CGFloat = 34.0
        static let iconPointSize: CGFloat = 18.0
        static let transitionDuration: TimeInterval = 0.24
        static let attachmentChipSize: CGFloat = 110.0
        static let attachmentChipSpacing: CGFloat = 10.0
        static let systemPromptVerticalInset: CGFloat = 8.0
        static let systemPromptIconPointSize: CGFloat = 14.0
        static let systemPromptRemoveIconPointSize: CGFloat = 10.0
        static let systemPromptHorizontalInset: CGFloat = 10.0
        static let systemPromptSpacing: CGFloat = 6.0
        static let systemPromptRemoveIconSpacing: CGFloat = 4.0
    }

    private let stackView = UIStackView()
    private let plusGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let waveformGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleLayoutStackView = UIStackView()
    private let inputRowContainerView = UIView()
    private let capsuleContentStackView = UIStackView()
    private let plusButton = UIButton(type: .system)
    private let waveformButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let systemPromptContainerView = UIView()
    private let systemPromptIconView = UIImageView()
    private let systemPromptTitleLabel = UILabel()
    private let systemPromptRemoveButton = UIButton(type: .system)
    private let attachmentPreviewContainerView = UIView()
    private let attachmentPreviewScrollView = UIScrollView()
    private let attachmentPreviewStackView = UIStackView()

    private var capsuleLayoutTopConstraint: NSLayoutConstraint!
    private var capsuleContentLeadingConstraint: NSLayoutConstraint!
    private var capsuleContentTrailingConstraint: NSLayoutConstraint!
    private var waveformWidthConstraint: NSLayoutConstraint!
    private var textHeightConstraint: NSLayoutConstraint!
    private var attachmentPreviewHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredTextWidth: CGFloat = 0.0
    private var isShowingSendControl = false
    private var isShowingStopControl = false
    private var isStreamingResponse = false
    private var pendingAttachments: [PendingAttachmentDisplay] = []
    private var selectedSystemPrompt: SelectedSystemPromptDisplay?
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    var onSend: ((SendTransition) -> Bool)?
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
        let previousIDs = Set(pendingAttachments.map(\.id))
        let nextIDs = Set(items.map(\.id))
        let existingChips = attachmentPreviewStackView.arrangedSubviews
            .compactMap { $0 as? ComposerAttachmentChipView }
        var chipsByID: [UUID: ComposerAttachmentChipView] = existingChips.reduce(into: [:]) { result, chip in
            result[chip.itemID] = chip
        }
        let removedChips = existingChips
            .filter { !nextIDs.contains($0.itemID) }
        let addedChips = items
            .filter { !previousIDs.contains($0.id) }
            .map(addAttachmentPreviewChip)
        for chip in addedChips {
            chipsByID[chip.itemID] = chip
        }

        for item in items {
            chipsByID[item.id]?.update(item: item)
        }
        orderAttachmentPreviewChips(for: items, chipsByID: chipsByID)

        pendingAttachments = items

        if !items.isEmpty {
            attachmentPreviewContainerView.isHidden = false
        }
        attachmentPreviewHeightConstraint.constant = items.isEmpty
            ? 0.0
            : Metrics.attachmentChipSize
        updateCapsulePreviewLayout()
        updateInputMode(animated: true)

        animatePreviewLayoutChange(
            animations: {
                addedChips.forEach { $0.isHidden = false }
                removedChips.forEach { $0.isHidden = true }
            },
            completion: {
                removedChips.forEach { $0.removeFromSuperview() }
                self.attachmentPreviewContainerView.isHidden = items.isEmpty
            }
        )
    }

    func setSelectedSystemPrompt(_ item: SelectedSystemPromptDisplay?) {
        selectedSystemPrompt = item
        systemPromptTitleLabel.text = item?.title
        systemPromptContainerView.isHidden = item == nil
        updateCapsulePreviewLayout()
        animatePreviewLayoutChange()
    }

    func setMessageText(_ text: String) {
        textView.text = text
        placeholderLabel.isHidden = !text.isEmpty
        updateInputMode(animated: true)
        updateTextHeight(animated: true)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureStackView()
        configurePlusButton()
        configureWaveformButton()
        configureCapsule()
        configureTraitObservation()
        updateInputMode(animated: false)
    }

    private func configureTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self]
        ) { (view: GlassComposerBarView, _) in
            view.updateFontsForCurrentContentSize()
            view.updateTextHeight(animated: false)
            view.onLayoutChange?()
        }
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
        plusButton.accessibilityLabel = String(localized: .generalAdd)
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
        waveformButton.accessibilityLabel = String(localized: .composerWaveform)
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

        capsuleLayoutStackView.axis = .vertical
        capsuleLayoutStackView.alignment = .fill
        capsuleLayoutStackView.spacing = Metrics.capsulePreviewGap
        capsuleLayoutStackView.translatesAutoresizingMaskIntoConstraints = false

        inputRowContainerView.translatesAutoresizingMaskIntoConstraints = false
        inputRowContainerView.clipsToBounds = false

        capsuleContentStackView.axis = .horizontal
        capsuleContentStackView.alignment = .bottom
        capsuleContentStackView.spacing = Metrics.capsuleContentSpacing
        capsuleContentStackView.translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        capsuleGlassView.contentView.addSubview(capsuleLayoutStackView)
        capsuleLayoutStackView.addArrangedSubview(systemPromptContainerView)
        capsuleLayoutStackView.addArrangedSubview(attachmentPreviewContainerView)
        capsuleLayoutStackView.addArrangedSubview(inputRowContainerView)

        inputRowContainerView.addSubview(capsuleContentStackView)
        capsuleContentStackView.addArrangedSubview(textView)
        inputRowContainerView.addSubview(sendButton)

        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Metrics.textMinHeight)
        capsuleLayoutTopConstraint = capsuleLayoutStackView.topAnchor.constraint(
            equalTo: capsuleGlassView.contentView.topAnchor,
            constant: Metrics.capsuleVerticalInset
        )
        capsuleContentLeadingConstraint = capsuleContentStackView.leadingAnchor.constraint(
            equalTo: inputRowContainerView.leadingAnchor,
            constant: Metrics.inputTextLeadingInset
        )
        capsuleContentTrailingConstraint = capsuleContentStackView.trailingAnchor.constraint(
            equalTo: inputRowContainerView.trailingAnchor
        )

        NSLayoutConstraint.activate([
            capsuleLayoutTopConstraint,
            capsuleLayoutStackView.leadingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.leadingAnchor,
                constant: Metrics.capsuleHorizontalInset
            ),
            capsuleLayoutStackView.trailingAnchor.constraint(
                equalTo: capsuleGlassView.contentView.trailingAnchor,
                constant: -Metrics.capsuleHorizontalInset
            ),
            capsuleLayoutStackView.bottomAnchor.constraint(
                equalTo: capsuleGlassView.contentView.bottomAnchor,
                constant: -Metrics.capsuleVerticalInset
            ),

            inputRowContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.sendButtonSize),

            capsuleContentStackView.topAnchor.constraint(equalTo: inputRowContainerView.topAnchor),
            capsuleContentLeadingConstraint,
            capsuleContentTrailingConstraint,
            capsuleContentStackView.bottomAnchor.constraint(
                equalTo: inputRowContainerView.bottomAnchor
            ),
            textHeightConstraint,

            sendButton.trailingAnchor.constraint(
                equalTo: inputRowContainerView.trailingAnchor
            ),
            sendButton.bottomAnchor.constraint(
                equalTo: inputRowContainerView.bottomAnchor
            ),
            sendButton.widthAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: Metrics.sendButtonSize)
        ])
    }

    private func configureSystemPromptPreview() {
        systemPromptContainerView.translatesAutoresizingMaskIntoConstraints = false
        systemPromptContainerView.clipsToBounds = false
        systemPromptContainerView.isHidden = true

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
        systemPromptContainerView.addSubview(systemPromptIconView)

        systemPromptTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        systemPromptTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        systemPromptTitleLabel.adjustsFontForContentSizeCategory = true
        systemPromptTitleLabel.textColor = .label
        systemPromptTitleLabel.lineBreakMode = .byTruncatingMiddle
        systemPromptTitleLabel.numberOfLines = 1
        systemPromptTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        systemPromptContainerView.addSubview(systemPromptTitleLabel)

        var removeConfig = UIButton.Configuration.plain()
        removeConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Metrics.systemPromptRemoveIconPointSize,
                weight: .semibold
            )
        )
        removeConfig.baseForegroundColor = .tertiaryLabel
        removeConfig.contentInsets = .zero
        systemPromptRemoveButton.configuration = removeConfig
        systemPromptRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        systemPromptRemoveButton.accessibilityLabel = String(localized: .composerRemoveSystemPrompt)
        systemPromptRemoveButton.setContentHuggingPriority(.required, for: .horizontal)
        systemPromptRemoveButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        systemPromptRemoveButton.addTarget(
            self,
            action: #selector(removeSystemPromptButtonPressed),
            for: .touchUpInside
        )
        systemPromptContainerView.addSubview(systemPromptRemoveButton)

        NSLayoutConstraint.activate([
            systemPromptIconView.leadingAnchor.constraint(
                equalTo: systemPromptContainerView.leadingAnchor,
                constant: Metrics.systemPromptHorizontalInset
            ),
            systemPromptIconView.centerYAnchor.constraint(equalTo: systemPromptTitleLabel.centerYAnchor),

            systemPromptTitleLabel.leadingAnchor.constraint(
                equalTo: systemPromptIconView.trailingAnchor,
                constant: Metrics.systemPromptSpacing
            ),
            systemPromptTitleLabel.topAnchor.constraint(
                equalTo: systemPromptContainerView.topAnchor,
                constant: Metrics.systemPromptVerticalInset
            ),
            systemPromptTitleLabel.bottomAnchor.constraint(
                equalTo: systemPromptContainerView.bottomAnchor,
                constant: -Metrics.systemPromptVerticalInset
            ),

            systemPromptRemoveButton.leadingAnchor.constraint(
                equalTo: systemPromptTitleLabel.trailingAnchor,
                constant: Metrics.systemPromptRemoveIconSpacing
            ),
            systemPromptRemoveButton.trailingAnchor.constraint(
                lessThanOrEqualTo: systemPromptContainerView.trailingAnchor,
                constant: -Metrics.systemPromptHorizontalInset
            ),
            systemPromptRemoveButton.centerYAnchor.constraint(equalTo: systemPromptTitleLabel.centerYAnchor)
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

        placeholderLabel.text = String(localized: .composerMessagePlaceholder)
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
        sendButton.accessibilityLabel = String(localized: .generalSend)
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

        guard onSend?(transition) == true else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        textView.text = ""
        placeholderLabel.isHidden = false
        updateInputMode(animated: true)
        updateTextHeight(animated: true)
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
            self.capsuleContentLeadingConstraint.constant = Metrics.inputTextLeadingInset
            self.capsuleContentTrailingConstraint.constant = shouldShowSendControl
                ? -(Metrics.sendButtonSize + Metrics.capsuleContentSpacing)
                : 0.0
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
            waveformButton.accessibilityLabel = String(localized: .composerStopGenerating)
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
            waveformButton.accessibilityLabel = String(localized: .composerWaveform)
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

    private func addAttachmentPreviewChip(for item: PendingAttachmentDisplay) -> ComposerAttachmentChipView {
        let chip = ComposerAttachmentChipView(item: item)
        chip.isHidden = true
        chip.onRemove = { [weak self] id in
            self?.onRemoveAttachment?(id)
        }
        chip.onPreview = { [weak self] id in
            self?.onPreviewAttachment?(id)
        }

        attachmentPreviewStackView.addArrangedSubview(chip)
        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: Metrics.attachmentChipSize),
            chip.heightAnchor.constraint(equalToConstant: Metrics.attachmentChipSize)
        ])
        return chip
    }

    private func orderAttachmentPreviewChips(
        for items: [PendingAttachmentDisplay],
        chipsByID: [UUID: ComposerAttachmentChipView]
    ) {
        for (targetIndex, item) in items.enumerated() {
            guard let chip = chipsByID[item.id],
                  let currentIndex = attachmentPreviewStackView.arrangedSubviews.firstIndex(of: chip),
                  currentIndex != targetIndex else {
                continue
            }

            attachmentPreviewStackView.removeArrangedSubview(chip)
            attachmentPreviewStackView.insertArrangedSubview(
                chip,
                at: min(targetIndex, attachmentPreviewStackView.arrangedSubviews.count)
            )
        }
    }

    private func updateCapsulePreviewLayout() {
        let hasPreviewContent = selectedSystemPrompt != nil || !pendingAttachments.isEmpty
        capsuleLayoutTopConstraint.constant = hasPreviewContent
            ? Metrics.capsulePreviewTopInset
            : Metrics.capsuleVerticalInset
    }

    private func animatePreviewLayoutChange(
        animations: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: 0.2,
            delay: 0.0,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: {
                animations?()
                self.superview?.layoutIfNeeded()
                self.layoutIfNeeded()
                self.onLayoutChange?()
            },
            completion: { _ in
                completion?()
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
    let itemID: UUID

    var onRemove: ((UUID) -> Void)?
    var onPreview: ((UUID) -> Void)?

    init(item: GlassComposerBarView.PendingAttachmentDisplay) {
        itemID = item.id
        super.init(frame: .zero)
        configure()
        update(item: item)
    }

    required init?(coder: NSCoder) {
        itemID = UUID()
        super.init(coder: coder)
    }

    func update(item: GlassComposerBarView.PendingAttachmentDisplay) {
        guard item.id == itemID else {
            return
        }

        backgroundView.accessibilityLabel = item.filename

        if item.isFile {
            imageView.isHidden = true
            fileIconView.isHidden = false
            filenameLabel.isHidden = false
            filenameLabel.text = item.filename
        } else {
            imageView.isHidden = false
            fileIconView.isHidden = true
            filenameLabel.isHidden = true
            imageView.image = item.image
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = Metrics.cornerRadius
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.clipsToBounds = true
        backgroundView.backgroundColor = UIColor.secondarySystemFill
        backgroundView.isUserInteractionEnabled = true
        backgroundView.isAccessibilityElement = true
        backgroundView.accessibilityHint = String(localized: .generalOpensPreview)
        backgroundView.accessibilityTraits = .button
        backgroundView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(previewTapped))
        )
        addSubview(backgroundView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        backgroundView.addSubview(imageView)

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
        filenameLabel.font = .systemFont(ofSize: Metrics.filenameFontSize, weight: .medium)
        filenameLabel.textColor = .label
        filenameLabel.textAlignment = .center
        filenameLabel.numberOfLines = 1
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        backgroundView.addSubview(filenameLabel)

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
        removeButton.accessibilityLabel = String(localized: .composerRemoveAttachment)
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

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

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
    }

    @objc private func previewTapped() {
        onPreview?(itemID)
    }
}
