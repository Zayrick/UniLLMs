//
//  ViewController.swift
//  UniLLMs
//
//  Created by Zayrick on 2026/5/9.
//

import UIKit

class ViewController: UIViewController {
    private let backgroundView = AppGradientBackgroundView()
    private let composerView = GlassComposerBarView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .appBackgroundMiddle
        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(backgroundView, at: 0)

        configureComposerView()
    }

    private func configureComposerView() {
        composerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(composerView)

        NSLayoutConstraint.activate([
            composerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14.0),
            composerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14.0),
            composerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8.0)
        ])
    }
}

private final class GlassComposerBarView: UIVisualEffectView, UITextViewDelegate {
    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let spacing: CGFloat = 8.0
        static let capsuleHorizontalInset: CGFloat = 12.0
        static let capsuleVerticalInset: CGFloat = 6.0
        static let textMinHeight: CGFloat = 32.0
        static let textMaxHeight: CGFloat = 118.0
        static let sendButtonSize: CGFloat = 34.0
    }

    private let stackView = UIStackView()
    private let plusGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let capsuleGlassView = UIVisualEffectView(effect: GlassComposerBarView.makeGlassEffect())
    private let plusButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)

    private var textHeightConstraint: NSLayoutConstraint!
    private var lastMeasuredTextWidth: CGFloat = 0.0

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
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateTextHeight(animated: true)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear

        configureStackView()
        configurePlusButton()
        configureCapsule()
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

        plusGlassView.translatesAutoresizingMaskIntoConstraints = false
        plusGlassView.cornerConfiguration = .capsule()
        plusGlassView.setContentHuggingPriority(.required, for: .horizontal)
        plusGlassView.setContentCompressionResistancePriority(.required, for: .horizontal)

        capsuleGlassView.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.cornerConfiguration = .corners(
            radius: .fixed(Double(Metrics.controlHeight * 0.5))
        )

        NSLayoutConstraint.activate([
            plusGlassView.widthAnchor.constraint(equalToConstant: Metrics.controlHeight),
            plusGlassView.heightAnchor.constraint(equalToConstant: Metrics.controlHeight),
            capsuleGlassView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight)
        ])
    }

    private func configurePlusButton() {
        plusButton.tintColor = .label
        plusButton.setImage(
            UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)
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

    private func configureCapsule() {
        configureTextView()
        configureSendButton()

        textView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        capsuleGlassView.contentView.addSubview(textView)
        capsuleGlassView.contentView.addSubview(sendButton)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Metrics.textMinHeight)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: capsuleGlassView.contentView.topAnchor, constant: Metrics.capsuleVerticalInset),
            textView.leadingAnchor.constraint(equalTo: capsuleGlassView.contentView.leadingAnchor, constant: Metrics.capsuleHorizontalInset),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8.0),
            textView.bottomAnchor.constraint(equalTo: capsuleGlassView.contentView.bottomAnchor, constant: -Metrics.capsuleVerticalInset),
            textHeightConstraint,

            sendButton.trailingAnchor.constraint(equalTo: capsuleGlassView.contentView.trailingAnchor, constant: -5.0),
            sendButton.bottomAnchor.constraint(equalTo: capsuleGlassView.contentView.bottomAnchor, constant: -5.0),
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
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        sendButton.configuration = configuration
        sendButton.accessibilityLabel = "Send"
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

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }
}

private final class AppGradientBackgroundView: UIView {
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isOpaque = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradientLayer.locations = [0.0, 0.5, 1.0]
        traitChangeRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AppGradientBackgroundView, _) in
            view.updateColors()
        }
        updateColors()
    }

    private func updateColors() {
        gradientLayer.colors = [
            UIColor.appBackgroundStart,
            UIColor.appBackgroundMiddle,
            UIColor.appBackgroundEnd
        ].map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}
