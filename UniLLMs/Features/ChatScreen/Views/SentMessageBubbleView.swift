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
        static let horizontalInset: CGFloat = 16.0
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
        static let systemPromptIconPointSize: CGFloat = 10.0
        static let systemPromptIndicatorSpacing: CGFloat = 4.0
        static let systemPromptToContentSpacing: CGFloat = 4.0
        static let historyToContentSpacing: CGFloat = 2.0
    }

    private static let contextMenuIdentifier = "SentMessageBubbleView.message" as NSString

    let messageID: UUID
    private let messageText: String
    private let attachments: [ChatAttachment]
    private let systemPromptTitle: String?
    private let backgroundView = UIView()
    private let label = UILabel()
    private let historyIndicatorView = HistoryIndicatorView()
    private var systemPromptIndicatorView: SystemPromptIndicatorView?
    private var attachmentRowStackView: UIStackView?
    private var labelBottomConstraint: NSLayoutConstraint!
    private var labelBottomToHistoryConstraint: NSLayoutConstraint!

    var onPreviewAttachment: ((ChatAttachment) -> Void)?
    var onResend: ((String, [ChatAttachment]) -> Void)?
    var onEdit: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var editHistoryCount = 0 {
        didSet {
            updateHistoryIndicatorVisibility()
        }
    }

    var currentCornerRadius: CGFloat {
        (isSingleLineLayout && attachments.isEmpty && systemPromptTitle == nil && editHistoryCount == 0)
            ? min(bounds.width, bounds.height) * 0.5
            : Metrics.multilineCornerRadius
    }

    convenience init(text: String) {
        self.init(messageID: UUID(), text: text, attachments: [])
    }

    init(
        messageID: UUID = UUID(),
        text: String,
        attachments: [ChatAttachment],
        systemPromptTitle: String? = nil
    ) {
        self.messageID = messageID
        messageText = text
        self.attachments = attachments
        self.systemPromptTitle = Self.normalizedSystemPromptTitle(systemPromptTitle)
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        messageID = UUID()
        messageText = ""
        attachments = []
        systemPromptTitle = nil
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        label.preferredMaxLayoutWidth = label.bounds.width
        let cornerRadius = currentCornerRadius
        updateCornerConfiguration(cornerRadius: cornerRadius)
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

        configureSystemPromptIndicatorIfNeeded()
        configureHistoryIndicator()

        labelBottomConstraint = label.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -Metrics.verticalInset
        )
        labelBottomToHistoryConstraint = label.bottomAnchor.constraint(
            equalTo: historyIndicatorView.topAnchor,
            constant: -Metrics.historyToContentSpacing
        )

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
            labelBottomConstraint,
            historyIndicatorView.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            historyIndicatorView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            historyIndicatorView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Metrics.verticalInset
            )
        ])

        configureAttachmentsRowIfNeeded()
        configureVerticalContentLayout()
        bringSubviewToFront(historyIndicatorView)

        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    private static func normalizedSystemPromptTitle(_ title: String?) -> String? {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    private func configureSystemPromptIndicatorIfNeeded() {
        guard let systemPromptTitle else {
            return
        }

        let indicatorView = SystemPromptIndicatorView(title: systemPromptTitle)
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicatorView)
        systemPromptIndicatorView = indicatorView
    }

    private func configureVerticalContentLayout() {
        if let systemPromptIndicatorView {
            NSLayoutConstraint.activate([
                systemPromptIndicatorView.topAnchor.constraint(
                    equalTo: topAnchor,
                    constant: Metrics.verticalInset
                ),
                systemPromptIndicatorView.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: Metrics.horizontalInset
                ),
                systemPromptIndicatorView.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingAnchor,
                    constant: -Metrics.horizontalInset
                )
            ])
        }

        if let attachmentRowStackView {
            let attachmentTopAnchor = systemPromptIndicatorView?.bottomAnchor ?? topAnchor
            let attachmentTopConstant = systemPromptIndicatorView == nil
                ? Metrics.verticalInset
                : Metrics.systemPromptToContentSpacing
            NSLayoutConstraint.activate([
                attachmentRowStackView.topAnchor.constraint(
                    equalTo: attachmentTopAnchor,
                    constant: attachmentTopConstant
                ),
                attachmentRowStackView.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: Metrics.horizontalInset
                ),
                attachmentRowStackView.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingAnchor,
                    constant: -Metrics.horizontalInset
                )
            ])
        }

        if let attachmentRowStackView {
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(
                    equalTo: attachmentRowStackView.bottomAnchor,
                    constant: messageText.isEmpty ? 0.0 : Metrics.attachmentToTextSpacing
                )
            ])
        } else if let systemPromptIndicatorView {
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(
                    equalTo: systemPromptIndicatorView.bottomAnchor,
                    constant: Metrics.systemPromptToContentSpacing
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
    }

    private func configureHistoryIndicator() {
        historyIndicatorView.isHidden = true
        historyIndicatorView.accessibilityHint = String(localized: .chatEditedHistoryHint)
        historyIndicatorView.addTarget(
            self,
            action: #selector(historyIndicatorPressed),
            for: .touchUpInside
        )
        historyIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(historyIndicatorView)
    }

    @objc private func historyIndicatorPressed() {
        onShowHistory?()
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
        container.accessibilityHint = String(localized: .generalOpensPreview)
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
        container.accessibilityLabel = String(localized: .chatAttachmentMoreCountFormat(hiddenAttachmentCount))

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

    private func updateCornerConfiguration(cornerRadius: CGFloat) {
        backgroundView.layer.cornerRadius = cornerRadius
    }

    private func updateHistoryIndicatorVisibility() {
        let showsHistoryIndicator = editHistoryCount > 0
        historyIndicatorView.isHidden = !showsHistoryIndicator
        labelBottomConstraint.isActive = !showsHistoryIndicator
        labelBottomToHistoryConstraint.isActive = showsHistoryIndicator
        setNeedsLayout()
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

    private func makeTargetedPreview() -> UITargetedPreview? {
        guard window != nil, !bounds.isEmpty else {
            return nil
        }

        let parameters = UIPreviewParameters()
        let visiblePath = makePreviewVisiblePath()
        parameters.backgroundColor = .clear
        parameters.visiblePath = visiblePath

        return UITargetedPreview(view: self, parameters: parameters)
    }

    private func makePreviewVisiblePath() -> UIBezierPath {
        UIBezierPath(
            roundedRect: bounds,
            cornerRadius: currentCornerRadius
        )
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(
            identifier: Self.contextMenuIdentifier,
            previewProvider: nil
        ) { [weak self, messageText, attachments, editHistoryCount] _ in
            var actions: [UIMenuElement] = []

            let copyAction = UIAction(
                title: String(localized: .chatCopy),
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = messageText
            }
            actions.append(copyAction)

            let resendAction = UIAction(
                title: String(localized: .chatResend),
                image: UIImage(systemName: "arrow.clockwise")
            ) { _ in
                self?.onResend?(messageText, attachments)
            }
            actions.append(resendAction)

            let editAction = UIAction(
                title: String(localized: .chatEditMessage),
                image: UIImage(systemName: "square.and.pencil")
            ) { _ in
                self?.onEdit?()
            }
            actions.append(editAction)

            if editHistoryCount > 0 {
                let historyTitle = editHistoryCount == 1
                    ? String(localized: .generalHistory)
                    : String(localized: .chatHistoryCountFormat(editHistoryCount))
                let historyAction = UIAction(
                    title: historyTitle,
                    image: UIImage(systemName: "clock")
                ) { _ in
                    self?.onShowHistory?()
                }
                actions.append(historyAction)
            }

            return UIMenu(title: "", children: actions)
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

    private final class SystemPromptIndicatorView: UIView {
        private let stackView = UIStackView()
        private let iconView = UIImageView()
        private let titleLabel = UILabel()

        init(title: String) {
            super.init(frame: .zero)
            configure(title: title)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure(title: "")
        }

        private func configure(title: String) {
            backgroundColor = .clear
            isAccessibilityElement = true
            accessibilityLabel = title
            setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

            iconView.image = UIImage(
                systemName: "text.quote",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: Metrics.systemPromptIconPointSize,
                    weight: .semibold
                )
            )
            iconView.tintColor = UIColor.white.withAlphaComponent(0.9)
            iconView.contentMode = .scaleAspectFit
            iconView.setContentHuggingPriority(.required, for: .horizontal)
            iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

            titleLabel.text = title
            titleLabel.font = .preferredFont(forTextStyle: .caption2)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            titleLabel.numberOfLines = 1
            titleLabel.lineBreakMode = .byTruncatingMiddle
            titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = Metrics.systemPromptIndicatorSpacing
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            stackView.addArrangedSubview(iconView)
            stackView.addArrangedSubview(titleLabel)
            addSubview(stackView)

            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: topAnchor),
                stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
                stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private final class HistoryIndicatorView: UIControl {
        private let title = String(localized: .chatEdited)
        private let titleLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configure()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure()
        }

        override var isHighlighted: Bool {
            didSet {
                updateTitle()
            }
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)

            titleLabel.font = .preferredFont(forTextStyle: .caption2)
            updateTitle()
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            let horizontalInset = max(0.0, (44.0 - bounds.width) * 0.5)
            let verticalInset = max(0.0, (28.0 - bounds.height) * 0.5)
            let hitBounds = bounds.insetBy(dx: -horizontalInset, dy: -verticalInset)
            return hitBounds.contains(point)
        }

        private func configure() {
            backgroundColor = .clear
            isAccessibilityElement = true
            accessibilityLabel = title
            accessibilityTraits = .button
            setContentHuggingPriority(.required, for: .horizontal)
            setContentCompressionResistancePriority(.required, for: .horizontal)

            titleLabel.font = .preferredFont(forTextStyle: .caption2)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.numberOfLines = 1
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(titleLabel)

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: topAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            updateTitle()
        }

        private func updateTitle() {
            let foregroundColor = UIColor.white.withAlphaComponent(isHighlighted ? 0.62 : 0.82)
            titleLabel.attributedText = NSAttributedString(
                string: title,
                attributes: [
                    .font: titleLabel.font as Any,
                    .foregroundColor: foregroundColor,
                    .underlineColor: foregroundColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            )
        }
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
