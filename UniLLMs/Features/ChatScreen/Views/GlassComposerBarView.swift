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

    private var capsuleContentLeadingConstraint: NSLayoutConstraint!
    private var capsuleContentTrailingConstraint: NSLayoutConstraint!
    private var waveformWidthConstraint: NSLayoutConstraint!
    private var textHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredTextWidth: CGFloat = 0.0
    private var isShowingSendControl = false
    private var isShowingStopControl = false
    private var isStreamingResponse = false

    var onSend: ((SendTransition) -> Void)?
    var onStop: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    var isSendingEnabled = true {
        didSet {
            updateSendControlAvailability()
        }
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
        updateInputMode(hasText: hasText, animated: true)
        updateTextHeight(animated: true)
    }

    func setStreamingResponseActive(_ isActive: Bool, animated: Bool) {
        guard isStreamingResponse != isActive else {
            return
        }

        isStreamingResponse = isActive
        updateWaveformButtonStyle()
        updateInputMode(hasText: !textView.text.isEmpty, animated: animated)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureStackView()
        configurePlusButton()
        configureWaveformButton()
        configureCapsule()
        updateInputMode(hasText: false, animated: false)
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

        capsuleContentStackView.axis = .horizontal
        capsuleContentStackView.alignment = .bottom
        capsuleContentStackView.spacing = Metrics.capsuleContentSpacing
        capsuleContentStackView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.contentView.addSubview(capsuleContentStackView)
        capsuleContentStackView.addArrangedSubview(textView)
        capsuleGlassView.contentView.addSubview(sendButton)

        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Metrics.textMinHeight)
        capsuleContentLeadingConstraint = capsuleContentStackView.leadingAnchor.constraint(
            equalTo: capsuleGlassView.contentView.leadingAnchor,
            constant: Metrics.capsuleHorizontalInset
        )
        capsuleContentTrailingConstraint = capsuleContentStackView.trailingAnchor.constraint(
            equalTo: capsuleGlassView.contentView.trailingAnchor,
            constant: -Metrics.capsuleHorizontalInset
        )

        NSLayoutConstraint.activate([
            capsuleContentStackView.topAnchor.constraint(
                equalTo: capsuleGlassView.contentView.topAnchor,
                constant: Metrics.capsuleVerticalInset
            ),
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

    @objc private func sendButtonPressed() {
        guard isSendingEnabled else {
            return
        }

        let messageText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else {
            return
        }

        layoutIfNeeded()
        textView.layoutIfNeeded()

        let sourceTextBounds = currentTextBounds()
        let sourceBackgroundBounds = sourceBubbleBounds(around: sourceTextBounds)
        let transition = SendTransition(
            text: messageText,
            backgroundGlobalFrame: textView.convert(sourceBackgroundBounds, to: nil)
        )

        textView.text = ""
        placeholderLabel.isHidden = false
        updateInputMode(hasText: false, animated: true)
        updateTextHeight(animated: true)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSend?(transition)
    }

    private func currentTextBounds() -> CGRect {
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        let usedRect = textView.layoutManager.usedRect(for: textView.textContainer)
        let textBounds = CGRect(
            x: usedRect.minX + textView.textContainerInset.left,
            y: usedRect.minY + textView.textContainerInset.top,
            width: usedRect.width,
            height: usedRect.height
        ).insetBy(dx: -1.0, dy: -1.0)

        let visibleTextBounds = textBounds.integral.intersection(textView.bounds)
        guard !visibleTextBounds.isNull,
              visibleTextBounds.width > 0.0,
              visibleTextBounds.height > 0.0 else {
            return textView.bounds
        }

        return visibleTextBounds
    }

    private func sourceBubbleBounds(around textBounds: CGRect) -> CGRect {
        var bubbleBounds = textBounds.insetBy(
            dx: -Metrics.capsuleHorizontalInset,
            dy: -Metrics.capsuleVerticalInset
        )

        if bubbleBounds.height < Metrics.controlHeight {
            let heightDelta = Metrics.controlHeight - bubbleBounds.height
            bubbleBounds.origin.y -= heightDelta * 0.5
            bubbleBounds.size.height = Metrics.controlHeight
        }

        return bubbleBounds.integral
    }

    private func updateInputMode(hasText: Bool, animated: Bool) {
        let shouldShowStopControl = isStreamingResponse
        let shouldShowSendControl = hasText && !shouldShowStopControl
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
}
