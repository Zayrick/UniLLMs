//
//  SentMessageBubbleView.swift
//  UniLLMs
//
//  Displays a sent user message bubble and supports the send transition layout.
//  Created by Zayrick on 2026/5/11.
//

import UIKit

final class SentMessageBubbleView: UIView, UIContextMenuInteractionDelegate {
    private enum Metrics {
        static let controlHeight: CGFloat = 44.0
        static let horizontalInset: CGFloat = 12.0
        static let verticalInset: CGFloat = 8.0
        static let multilineCornerRadius: CGFloat = 22.0
    }

    private static let contextMenuIdentifier = "SentMessageBubbleView.message" as NSString

    private let messageText: String
    private let backgroundView = UIView()
    private let label = UILabel()
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    var currentCornerRadius: CGFloat {
        isSingleLineLayout ? bounds.height * 0.5 : Metrics.multilineCornerRadius
    }

    init(text: String) {
        messageText = text
        super.init(frame: .zero)
        configure()
        configureTraitObservation()
    }

    required init?(coder: NSCoder) {
        messageText = ""
        super.init(coder: coder)
        configure()
        configureTraitObservation()
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

        backgroundView.backgroundColor = .systemBlue
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.cornerRadius = Metrics.controlHeight * 0.5
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        label.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
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

        applyMessageText()
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    private func configureTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self]
        ) { (view: SentMessageBubbleView, _) in
            view.applyMessageText()
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }
    }

    private func applyMessageText() {
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = Self.systemLineSpacing(for: font)
        paragraphStyle.paragraphSpacing = Self.systemParagraphSpacing(for: font)

        label.font = font
        label.attributedText = NSAttributedString(
            string: messageText,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func updateCornerConfiguration() {
        backgroundView.layer.cornerRadius = currentCornerRadius
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

    private func makeTargetedPreview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        let visiblePath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: currentCornerRadius
        )
        parameters.backgroundColor = .clear
        parameters.visiblePath = visiblePath
        parameters.shadowPath = visiblePath

        return UITargetedPreview(view: self, parameters: parameters)
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(
            identifier: Self.contextMenuIdentifier,
            previewProvider: nil
        ) { [messageText] _ in
            let copyAction = UIAction(
                title: "Copy",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = messageText
            }

            return UIMenu(title: "", children: [copyAction])
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        highlightPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        makeTargetedPreview()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        makeTargetedPreview()
    }

    private static func systemParagraphSpacing(for font: UIFont) -> CGFloat {
        ceil(max(font.leading, font.lineHeight - font.pointSize))
    }

    private static func systemLineSpacing(for font: UIFont) -> CGFloat {
        ceil(max(font.leading, font.lineHeight - font.pointSize))
    }
}
