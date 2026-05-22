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
        static let maximumVisibleAttachmentCount = 3
        static let attachmentChipSize: CGFloat = 48.0
        static let attachmentChipSpacing: CGFloat = 6.0
        static let overflowChipWidth: CGFloat = 34.0
        static let attachmentChipCornerRadius: CGFloat = 12.0
        static let attachmentToTextSpacing: CGFloat = 8.0
        static let fileIconPointSize: CGFloat = 22.0
        static let filenameFontSize: CGFloat = 9.0
        static let overflowFontSize: CGFloat = 13.0
    }

    private static let contextMenuIdentifier = "SentMessageBubbleView.message" as NSString

    private let messageText: String
    private let attachments: [ChatAttachment]
    private let backgroundView = UIView()
    private let label = UILabel()
    private var attachmentRowStackView: UIStackView?

    var onPreviewAttachment: ((ChatAttachment) -> Void)?

    var currentCornerRadius: CGFloat {
        (isSingleLineLayout && attachments.isEmpty) ? bounds.height * 0.5 : Metrics.multilineCornerRadius
    }

    convenience init(text: String) {
        self.init(text: text, attachments: [])
    }

    init(text: String, attachments: [ChatAttachment]) {
        messageText = text
        self.attachments = attachments
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        messageText = ""
        attachments = []
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

        backgroundView.backgroundColor = .systemBlue
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.cornerRadius = Metrics.controlHeight * 0.5
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.text = messageText
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = messageText.isEmpty
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
            label.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Metrics.verticalInset
            )
        ])

        configureAttachmentsRowIfNeeded()

        if let attachmentRowStackView {
            NSLayoutConstraint.activate([
                attachmentRowStackView.topAnchor.constraint(
                    equalTo: topAnchor,
                    constant: Metrics.verticalInset
                ),
                attachmentRowStackView.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: Metrics.horizontalInset
                ),
                attachmentRowStackView.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingAnchor,
                    constant: -Metrics.horizontalInset
                ),
                label.topAnchor.constraint(
                    equalTo: attachmentRowStackView.bottomAnchor,
                    constant: messageText.isEmpty ? 0.0 : Metrics.attachmentToTextSpacing
                )
            ])
        } else {
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(
                    equalTo: topAnchor,
                    constant: Metrics.verticalInset
                )
            ])
        }

        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    private func configureAttachmentsRowIfNeeded() {
        guard !attachments.isEmpty else { return }

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Metrics.attachmentChipSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let visibleAttachments = attachments.prefix(Metrics.maximumVisibleAttachmentCount)
        for attachment in visibleAttachments {
            let chip = makeAttachmentChip(for: attachment)
            row.addArrangedSubview(chip)
            chip.widthAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
            chip.heightAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
        }

        let hiddenAttachmentCount = attachments.count - visibleAttachments.count
        if hiddenAttachmentCount > 0 {
            let chip = makeOverflowChip(hiddenAttachmentCount: hiddenAttachmentCount)
            row.addArrangedSubview(chip)
            chip.widthAnchor.constraint(equalToConstant: Metrics.overflowChipWidth).isActive = true
            chip.heightAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
        }

        attachmentRowStackView = row
    }

    private func makeAttachmentChip(for attachment: ChatAttachment) -> UIView {
        let container = AttachmentChipView(attachment: attachment)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = Metrics.attachmentChipCornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        container.isAccessibilityElement = true
        container.accessibilityLabel = attachment.filename
        container.accessibilityHint = "Opens a preview"
        container.accessibilityTraits = .button

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(attachmentChipTapped(_:)))
        container.addGestureRecognizer(tapGesture)

        switch attachment.kind {
        case .image:
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            if let url = ChatAttachmentStore.shared.fileURL(for: attachment),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                imageView.image = image
            } else {
                imageView.image = UIImage(
                    systemName: "photo",
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: Metrics.fileIconPointSize,
                        weight: .semibold
                    )
                )
                imageView.tintColor = .white
                imageView.contentMode = .center
            }
            container.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        case .file:
            let iconView = UIImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .white
            iconView.image = UIImage(
                systemName: "doc.text.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: Metrics.fileIconPointSize,
                    weight: .semibold
                )
            )
            container.addSubview(iconView)

            let nameLabel = UILabel()
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            nameLabel.text = attachment.filename
            nameLabel.font = .systemFont(ofSize: Metrics.filenameFontSize, weight: .medium)
            nameLabel.textColor = .white
            nameLabel.textAlignment = .center
            nameLabel.numberOfLines = 1
            nameLabel.lineBreakMode = .byTruncatingMiddle
            container.addSubview(nameLabel)

            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -4.0),

                nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 3.0),
                nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -3.0),
                nameLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4.0)
            ])
        }

        return container
    }

    private func makeOverflowChip(hiddenAttachmentCount: Int) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = Metrics.attachmentChipCornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        container.isAccessibilityElement = true
        container.accessibilityLabel = "\(hiddenAttachmentCount) more attachments"

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "+\(hiddenAttachmentCount)"
        label.font = .systemFont(ofSize: Metrics.overflowFontSize, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 3.0),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -3.0),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    @objc private func attachmentChipTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let chip = recognizer.view as? AttachmentChipView else {
            return
        }

        onPreviewAttachment?(chip.attachment)
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

    private final class AttachmentChipView: UIView {
        let attachment: ChatAttachment

        init(attachment: ChatAttachment) {
            self.attachment = attachment
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            return nil
        }
    }
}
