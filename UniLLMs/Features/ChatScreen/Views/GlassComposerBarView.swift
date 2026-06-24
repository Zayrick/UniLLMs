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
        let title: String
    }

    struct ReasoningConfigurationItem: Equatable {
        let value: Int
        let title: String
    }

    struct ReasoningConfigurationDisplay: Equatable {
        static let empty = ReasoningConfigurationDisplay(
            items: [],
            resolvedValue: ReasoningEffortConfiguration.omitValue,
            positiveLevelCount: 0,
            activePositiveLevelCount: 0
        )

        let items: [ReasoningConfigurationItem]
        let resolvedValue: Int
        let positiveLevelCount: Int
        let activePositiveLevelCount: Int
    }

    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let capsuleHorizontalInset: CGFloat = 7.0
        static let capsulePreviewTopInset: CGFloat = 7.0
        static let capsuleVerticalInset: CGFloat = 5.0
        static let capsulePreviewGap: CGFloat = 7.0
        static let capsuleContentSpacing: CGFloat = 6.0
        static let textMinHeight: CGFloat = 32.0
        static let textMaxHeight: CGFloat = 118.0
        static let sendButtonSize: CGFloat = 34.0
        static let plusIconPointSize: CGFloat = 16.0
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

    private let capsuleLayoutStackView = UIStackView()
    private let inputRowContainerView = UIView()
    private let capsuleContentStackView = UIStackView()
    private let plusButton = UIButton(type: .system)
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
    private var textHeightConstraint: NSLayoutConstraint!
    private var attachmentPreviewHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredTextWidth: CGFloat = 0.0
    private var hasSendableContent = false
    private var isShowingStopControl = false
    private var isStreamingResponse = false
    private var pendingAttachments: [PendingAttachmentDisplay] = []
    private var selectedSystemPrompt: SelectedSystemPromptDisplay?
    private var reasoningConfiguration = ReasoningConfigurationDisplay.empty
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    var onSend: ((SendTransition) -> Void)?
    var onStop: (() -> Void)?
    var onPlusTap: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    var onRemoveAttachment: ((UUID) -> Void)?
    var onPreviewAttachment: ((UUID) -> Void)?
    var onRemoveSystemPrompt: (() -> Void)?
    var onReasoningConfigurationChange: ((Int) -> Void)?
    var isSendingEnabled = true {
        didSet {
            updateSendControlAvailability()
        }
    }

    /// Source view used as the morph anchor for presentations triggered by the plus button.
    var plusSourceView: UIView {
        self
    }

    init() {
        super.init(effect: GlassComposerBarView.makeGlassEffect())
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        effect = GlassComposerBarView.makeGlassEffect()
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
        updateInputMode(animated: animated)
    }

    func currentDraftText() -> String {
        textView.text
    }

    func setDraftText(_ text: String, animated: Bool) {
        textView.text = text
        placeholderLabel.isHidden = !text.isEmpty
        updateInputMode(animated: animated)
        updateTextHeight(animated: animated)
        onLayoutChange?()
    }

    func focusInput() {
        textView.becomeFirstResponder()
    }

    func setPendingAttachments(_ items: [PendingAttachmentDisplay]) {
        pendingAttachments = items

        attachmentPreviewStackView.arrangedSubviews.forEach {
            attachmentPreviewStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        items.forEach { item in
            let chip = ComposerAttachmentChipView(item: item)
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
        }

        attachmentPreviewContainerView.isHidden = items.isEmpty
        attachmentPreviewHeightConstraint.constant = items.isEmpty
            ? 0.0
            : Metrics.attachmentChipSize
        updateCapsulePreviewLayout()
        updateInputMode(animated: true)
        onLayoutChange?()
    }

    func setSelectedSystemPrompt(_ item: SelectedSystemPromptDisplay?) {
        selectedSystemPrompt = item
        systemPromptTitleLabel.text = item?.title
        systemPromptContainerView.isHidden = item == nil
        updateCapsulePreviewLayout()
        onLayoutChange?()
    }

    func setReasoningConfiguration(_ configuration: ReasoningConfigurationDisplay) {
        reasoningConfiguration = configuration
        updateSendButtonStyle()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        cornerConfiguration = .corners(
            radius: .fixed(Double(Metrics.controlHeight * 0.5))
        )

        configurePlusButton()
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

    private func configurePlusButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.plusIconPointSize, weight: .regular)
        )
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        plusButton.configuration = configuration
        plusButton.accessibilityLabel = String(localized: .generalAdd)
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.setContentHuggingPriority(.required, for: .horizontal)
        plusButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        plusButton.addTarget(self, action: #selector(plusButtonPressed), for: .touchUpInside)
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

        contentView.addSubview(capsuleLayoutStackView)
        capsuleLayoutStackView.addArrangedSubview(systemPromptContainerView)
        capsuleLayoutStackView.addArrangedSubview(attachmentPreviewContainerView)
        capsuleLayoutStackView.addArrangedSubview(inputRowContainerView)

        inputRowContainerView.addSubview(capsuleContentStackView)
        capsuleContentStackView.addArrangedSubview(plusButton)
        capsuleContentStackView.addArrangedSubview(textView)
        capsuleContentStackView.addArrangedSubview(sendButton)

        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Metrics.textMinHeight)
        capsuleLayoutTopConstraint = capsuleLayoutStackView.topAnchor.constraint(
            equalTo: contentView.topAnchor,
            constant: Metrics.capsuleVerticalInset
        )

        NSLayoutConstraint.activate([
            capsuleLayoutTopConstraint,
            capsuleLayoutStackView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Metrics.capsuleHorizontalInset
            ),
            capsuleLayoutStackView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Metrics.capsuleHorizontalInset
            ),
            capsuleLayoutStackView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Metrics.capsuleVerticalInset
            ),

            inputRowContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.sendButtonSize),

            capsuleContentStackView.topAnchor.constraint(equalTo: inputRowContainerView.topAnchor),
            capsuleContentStackView.leadingAnchor.constraint(equalTo: inputRowContainerView.leadingAnchor),
            capsuleContentStackView.trailingAnchor.constraint(equalTo: inputRowContainerView.trailingAnchor),
            capsuleContentStackView.bottomAnchor.constraint(
                equalTo: inputRowContainerView.bottomAnchor
            ),
            textHeightConstraint,

            plusButton.widthAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            plusButton.heightAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
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
        sendButton.showsMenuAsPrimaryAction = false
        sendButton.addTarget(self, action: #selector(sendButtonPressed), for: .touchUpInside)
        updateSendButtonStyle()
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
        guard !isShowingStopControl else {
            onStop?()
            return
        }

        sendMessage()
    }

    private func sendMessage() {
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
            backgroundGlobalFrame: convert(bounds, to: nil)
        )

        textView.text = ""
        placeholderLabel.isHidden = false
        updateInputMode(animated: true)
        updateTextHeight(animated: true)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSend?(transition)
    }

    private func updateSendReasoningMenu() {
        guard !isShowingStopControl, reasoningConfiguration.items.count > 1 else {
            sendButton.menu = nil
            sendButton.accessibilityHint = nil
            return
        }

        let selectedValue = reasoningConfiguration.resolvedValue
        let groupedItems = [
            reasoningConfiguration.items.filter { $0.value <= ReasoningEffortConfiguration.omitValue },
            reasoningConfiguration.items.filter { $0.value == ReasoningEffortConfiguration.disabledValue },
            reasoningConfiguration.items.filter { $0.value > ReasoningEffortConfiguration.disabledValue }
        ]
        let sections = groupedItems.compactMap { items -> UIMenu? in
            guard !items.isEmpty else {
                return nil
            }
            let actions = items.map { item in
                UIAction(
                    title: item.title,
                    image: reasoningConfigurationImage(for: item.value),
                    state: item.value == selectedValue ? .on : .off
                ) { [weak self] _ in
                    self?.onReasoningConfigurationChange?(item.value)
                }
            }
            return UIMenu(options: [.displayInline, .singleSelection], children: actions)
        }

        sendButton.menu = UIMenu(
            title: String(localized: .composerReasoningEffortMenuTitle),
            children: sections
        )
        sendButton.accessibilityHint = String(localized: .composerReasoningEffortHint)
    }

    private func reasoningConfigurationImage(for value: Int) -> UIImage? {
        if value <= ReasoningEffortConfiguration.omitValue {
            return UIImage(systemName: "arrow.up.circle")
        }
        if value == ReasoningEffortConfiguration.disabledValue {
            return UIImage(systemName: "slash.circle")
        }
        if value <= 2 {
            return UIImage(systemName: "brain")
        }
        if value == 3 {
            return UIImage(systemName: "brain.head.profile")
        }
        return UIImage(systemName: "sparkles")
    }

    private func updateInputMode(animated: Bool) {
        let hasText = !textView.text.isEmpty
        let hasContent = hasText || !pendingAttachments.isEmpty
        let shouldShowStopControl = isStreamingResponse
        let stateChanged = hasContent != hasSendableContent
            || shouldShowStopControl != isShowingStopControl
        hasSendableContent = hasContent
        isShowingStopControl = shouldShowStopControl

        guard stateChanged || !animated else {
            return
        }

        updateSendButtonStyle()
        updateSendControlAvailability()

        let applyTargetState = { [self] in
            self.sendButton.alpha = hasContent || shouldShowStopControl ? 1.0 : 0.52
            self.superview?.layoutIfNeeded()
            self.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: Metrics.transitionDuration,
                delay: 0.0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: {
                    applyTargetState()
                }
            )
        } else {
            applyTargetState()
        }
    }

    private func updateSendControlAvailability() {
        let canUseActionControl = isShowingStopControl || isSendingEnabled
        sendButton.isEnabled = canUseActionControl
        sendButton.isUserInteractionEnabled = canUseActionControl
    }

    private func updateSendButtonStyle() {
        var configuration = sendButton.configuration ?? UIButton.Configuration.prominentClearGlass()
        configuration.image = Self.makeSendButtonIconImage(
            systemName: isShowingStopControl ? "stop.fill" : "arrow.up",
            activeSegments: isShowingStopControl ? 0 : reasoningConfiguration.activePositiveLevelCount,
            totalSegments: isShowingStopControl ? 0 : reasoningConfiguration.positiveLevelCount,
            displayScale: traitCollection.displayScale
        )
        configuration.baseBackgroundColor = isShowingStopControl ? .systemRed : .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        sendButton.configuration = configuration
        sendButton.accessibilityLabel = isShowingStopControl
            ? String(localized: .composerStopGenerating)
            : String(localized: .generalSend)
        updateSendReasoningMenu()
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
        onLayoutChange?()
    }

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }

    private static func makeSendButtonIconImage(
        systemName: String,
        activeSegments: Int,
        totalSegments: Int,
        displayScale: CGFloat
    ) -> UIImage? {
        let imageSize = CGSize(width: 25.0, height: 25.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale > 0.0 ? displayScale : 1.0
        format.opaque = false

        return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: imageSize)
            let litSegments = max(0, min(activeSegments, totalSegments))
            let showsReasoningRing = activeSegments >= ReasoningEffortConfiguration.disabledValue
                && totalSegments > 0
            if showsReasoningRing {
                drawReasoningRing(
                    in: bounds,
                    activeSegments: litSegments,
                    totalSegments: totalSegments,
                    context: context.cgContext
                )
            }

            let symbolPointSize: CGFloat = showsReasoningRing ? 14.0 : 17.0
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .bold)
            guard let symbol = UIImage(
                systemName: systemName,
                withConfiguration: symbolConfiguration
            )?.withTintColor(.white, renderingMode: .alwaysOriginal) else {
                return
            }

            let symbolSize = symbol.size
            symbol.draw(
                at: CGPoint(
                    x: bounds.midX - symbolSize.width * 0.5,
                    y: bounds.midY - symbolSize.height * 0.5
                )
            )
        }
    }

    private static func drawReasoningRing(
        in bounds: CGRect,
        activeSegments: Int,
        totalSegments: Int,
        context: CGContext
    ) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.5 - 1.4
        let segmentAngle = CGFloat.pi * 2.0 / CGFloat(totalSegments)
        let gapAngle = totalSegments == 1 ? CGFloat(0.0) : min(CGFloat(0.22), segmentAngle * 0.28)
        let startAngle = -CGFloat.pi * 0.5

        context.setLineWidth(2.0)
        context.setLineCap(.round)

        for index in 0..<totalSegments {
            let segmentStart = startAngle + CGFloat(index) * segmentAngle + gapAngle * 0.5
            let segmentEnd = startAngle + CGFloat(index + 1) * segmentAngle - gapAngle * 0.5
            context.setStrokeColor(UIColor.white.withAlphaComponent(index < activeSegments ? 0.95 : 0.24).cgColor)
            context.addArc(
                center: center,
                radius: radius,
                startAngle: segmentStart,
                endAngle: segmentEnd,
                clockwise: false
            )
            context.strokePath()
        }
    }

    private func updateCapsulePreviewLayout() {
        let hasPreviewContent = selectedSystemPrompt != nil || !pendingAttachments.isEmpty
        capsuleLayoutTopConstraint.constant = hasPreviewContent
            ? Metrics.capsulePreviewTopInset
            : Metrics.capsuleVerticalInset
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
        backgroundView.accessibilityHint = String(localized: .generalOpensPreview)
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
