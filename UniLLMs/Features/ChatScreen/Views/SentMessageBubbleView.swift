//
//  SentMessageBubbleView.swift
//  UniLLMs
//
//  Displays a sent user message bubble and supports the send transition layout.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class SentMessageBubbleView: UIView {
    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let horizontalInset: CGFloat = 12.0
        static let verticalInset: CGFloat = 8.0
        static let multilineCornerRadius: CGFloat = 22.0
    }

    private let messageText: String
    private let glassView = UIVisualEffectView(effect: SentMessageBubbleView.makeGlassEffect())
    private let label = UILabel()

    var currentCornerRadius: CGFloat {
        isSingleLineLayout ? bounds.height * 0.5 : Metrics.multilineCornerRadius
    }

    init(text: String) {
        messageText = text
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        messageText = ""
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        label.preferredMaxLayoutWidth = label.bounds.width
        updateCornerConfiguration()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        glassView.backgroundColor = .clear
        glassView.isUserInteractionEnabled = false
        glassView.cornerConfiguration = .capsule()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        label.text = messageText
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            label.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            label.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Metrics.verticalInset
            ),
            label.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Metrics.verticalInset
            )
        ])
    }

    private func updateCornerConfiguration() {
        if isSingleLineLayout {
            glassView.cornerConfiguration = .capsule()
        } else {
            glassView.cornerConfiguration = .corners(
                radius: .fixed(Double(Metrics.multilineCornerRadius))
            )
        }
    }

    private var isSingleLineLayout: Bool {
        guard !messageText.contains("\n"),
              label.bounds.width > 0.0,
              let font = label.font else {
            return false
        }

        let fittingSize = label.sizeThatFits(
            CGSize(width: label.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        )
        return fittingSize.height <= ceil(font.lineHeight * 1.25)
    }

    private static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        return effect
    }
}
