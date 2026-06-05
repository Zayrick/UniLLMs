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
        static let historyCutoutDiameter: CGFloat = 18.0
        static let historyIndicatorCenterInset: CGFloat = 7.0
        static let historyIndicatorSize: CGFloat = 14.0
        static let historyIconPointSize: CGFloat = 12.0
    }

    private static let contextMenuIdentifier = "SentMessageBubbleView.message" as NSString

    let messageID: UUID
    private let messageText: String
    private let attachments: [ChatAttachment]
    private var attachmentDisplays: [ChatAttachmentPreviewDisplay]
    private let backgroundView = UIView()
    private let backgroundMaskLayer = CAShapeLayer()
    private let label = UILabel()
    private let historyIndicatorView = UIImageView()
    private var attachmentRowStackView: UIStackView?
    private var pendingContextMenuAction: (() -> Void)?
    private var isContextMenuDisplayed = false

    var onPreviewAttachment: ((ChatAttachment) -> Void)?
    var onResend: ((String, [ChatAttachment]) -> Void)?
    var onEditAndResend: ((String, [ChatAttachment]) -> Void)?
    var onShowHistory: (() -> Void)?
    var editHistoryCount = 0 {
        didSet {
            updateHistoryIndicatorVisibility()
        }
    }

    var currentCornerRadius: CGFloat {
        (isSingleLineLayout && attachments.isEmpty)
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
        attachmentDisplays: [ChatAttachmentPreviewDisplay]? = nil
    ) {
        self.messageID = messageID
        messageText = text
        self.attachments = attachments
        self.attachmentDisplays = attachmentDisplays ?? ChatAttachmentPreviewDisplay.placeholders(for: attachments)
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        messageID = UUID()
        messageText = ""
        attachments = []
        attachmentDisplays = []
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        label.preferredMaxLayoutWidth = label.bounds.width
        let cornerRadius = currentCornerRadius
        updateCornerConfiguration(cornerRadius: cornerRadius)
        updateHistoryCutoutMask(cornerRadius: cornerRadius)
    }

    func updateAttachmentDisplays(_ displays: [ChatAttachmentPreviewDisplay]) {
        guard displays.map(\.id) == attachmentDisplays.map(\.id) else {
            return
        }

        attachmentDisplays = displays
        guard let attachmentRowStackView else {
            return
        }

        let chipsByID = attachmentRowStackView.arrangedSubviews
            .compactMap { $0 as? AttachmentChipView }
            .reduce(into: [UUID: AttachmentChipView]()) { result, chip in
                result[chip.itemID] = chip
            }
        for display in displays.prefix(Metrics.maximumVisibleAttachmentCount) {
            chipsByID[display.id]?.update(display: display)
        }
        setNeedsLayout()
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

        configureHistoryIndicator()

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
            ),
            historyIndicatorView.widthAnchor.constraint(equalToConstant: Metrics.historyIndicatorSize),
            historyIndicatorView.heightAnchor.constraint(equalToConstant: Metrics.historyIndicatorSize),
            historyIndicatorView.centerXAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Metrics.historyIndicatorCenterInset
            ),
            historyIndicatorView.centerYAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Metrics.historyIndicatorCenterInset
            )
        ])

        configureAttachmentsRowIfNeeded()
        bringSubviewToFront(historyIndicatorView)

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

    private func configureHistoryIndicator() {
        backgroundMaskLayer.fillColor = UIColor.black.cgColor
        backgroundMaskLayer.fillRule = .evenOdd

        historyIndicatorView.image = UIImage(systemName: "clock")
        historyIndicatorView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Metrics.historyIconPointSize,
            weight: .semibold
        )
        historyIndicatorView.tintColor = .systemBlue
        historyIndicatorView.contentMode = .scaleAspectFit
        historyIndicatorView.isHidden = true
        historyIndicatorView.isAccessibilityElement = false
        historyIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(historyIndicatorView)
    }

    private func configureAttachmentsRowIfNeeded() {
        guard !attachments.isEmpty else { return }

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Metrics.attachmentChipSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let visibleDisplays = attachmentDisplays.prefix(Metrics.maximumVisibleAttachmentCount)
        for display in visibleDisplays {
            let chip = makeAttachmentChip(for: display)
            row.addArrangedSubview(chip)
            chip.widthAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
            chip.heightAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
        }

        let hiddenAttachmentCount = attachmentDisplays.count - visibleDisplays.count
        if hiddenAttachmentCount > 0 {
            let chip = makeOverflowChip(hiddenAttachmentCount: hiddenAttachmentCount)
            row.addArrangedSubview(chip)
            chip.widthAnchor.constraint(equalToConstant: Metrics.overflowChipWidth).isActive = true
            chip.heightAnchor.constraint(equalToConstant: Metrics.attachmentChipSize).isActive = true
        }

        attachmentRowStackView = row
    }

    private func makeAttachmentChip(for display: ChatAttachmentPreviewDisplay) -> UIView {
        let container = AttachmentChipView(display: display)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(attachmentChipTapped(_:)))
        container.addGestureRecognizer(tapGesture)
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
        backgroundView.layer.mask = showsHistoryIndicator ? backgroundMaskLayer : nil
        setNeedsLayout()
    }

    private func updateHistoryCutoutMask(cornerRadius: CGFloat) {
        guard editHistoryCount > 0 else {
            backgroundMaskLayer.path = nil
            return
        }

        let bounds = backgroundView.bounds
        guard !bounds.isEmpty else {
            backgroundMaskLayer.path = nil
            return
        }

        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        path.append(UIBezierPath(ovalIn: historyCutoutRect(in: bounds)))
        path.usesEvenOddFillRule = true

        backgroundMaskLayer.frame = bounds
        backgroundMaskLayer.path = path.cgPath
    }

    private func historyCutoutRect(in bounds: CGRect) -> CGRect {
        let center = CGPoint(
            x: bounds.maxX - Metrics.historyIndicatorCenterInset,
            y: bounds.maxY - Metrics.historyIndicatorCenterInset
        )
        let radius = Metrics.historyCutoutDiameter * 0.5

        return CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: Metrics.historyCutoutDiameter,
            height: Metrics.historyCutoutDiameter
        )
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
        let visiblePath = makePreviewVisiblePath()
        parameters.backgroundColor = .clear
        parameters.visiblePath = visiblePath

        return UITargetedPreview(view: self, parameters: parameters)
    }

    private func makePreviewVisiblePath() -> UIBezierPath {
        let path = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: currentCornerRadius
        )

        if editHistoryCount > 0 {
            let indicatorPathRect = historyCutoutRect(in: bounds).insetBy(dx: -1.0, dy: -1.0)
            path.append(UIBezierPath(ovalIn: indicatorPathRect))
        }

        return path
    }

    private func performAfterContextMenuDismissal(_ action: @escaping () -> Void) {
        guard isContextMenuDisplayed else {
            action()
            return
        }

        pendingContextMenuAction = action
    }

    private func performPendingContextMenuActionIfNeeded() {
        guard let action = pendingContextMenuAction else {
            return
        }

        pendingContextMenuAction = nil
        action()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(
            identifier: Self.contextMenuIdentifier,
            previewProvider: nil
        ) { [weak self, editHistoryCount] _ in
            self?.makeContextMenu(editHistoryCount: editHistoryCount)
        }
    }

    func makeContextMenu(editHistoryCount: Int) -> UIMenu {
        let items = SentMessageBubbleActionMenuPolicy.makeItems(editHistoryCount: editHistoryCount)
        let actions = items.map { item in
            UIAction(
                title: item.title,
                image: UIImage(systemName: item.systemImageName)
            ) { [weak self] _ in
                self?.performMessageAction(item.action)
            }
        }

        return UIMenu(title: "", children: actions)
    }

    private func performMessageAction(_ action: SentMessageBubbleAction) {
        makeMessageActionRouter().perform(action)
    }

    private func makeMessageActionRouter() -> SentMessageBubbleActionRouter {
        SentMessageBubbleActionRouter(
            messageText: messageText,
            attachments: attachments,
            copyText: { text in
                UIPasteboard.general.string = text
            },
            performAfterDismissal: { [weak self] action in
                self?.performAfterContextMenuDismissal(action)
            },
            resend: { [weak self] text, attachments in
                self?.onResend?(text, attachments)
            },
            editAndResend: { [weak self] text, attachments in
                self?.onEditAndResend?(text, attachments)
            },
            showHistory: { [weak self] in
                self?.onShowHistory?()
            }
        )
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

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        isContextMenuDisplayed = true
        pendingContextMenuAction = nil
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        let completion = {
            self.isContextMenuDisplayed = false
            self.performPendingContextMenuActionIfNeeded()
        }

        if let animator {
            animator.addCompletion(completion)
        } else {
            completion()
        }
    }

    private final class AttachmentChipView: UIView {
        private let imageView = UIImageView()
        private let fileIconView = UIImageView()
        private let filenameLabel = UILabel()
        private(set) var attachment: ChatAttachment

        var itemID: UUID {
            attachment.id
        }

        init(display: ChatAttachmentPreviewDisplay) {
            attachment = display.attachment
            super.init(frame: .zero)
            configure()
            update(display: display)
        }

        required init?(coder: NSCoder) {
            return nil
        }

        func update(display: ChatAttachmentPreviewDisplay) {
            guard display.id == itemID else {
                return
            }

            attachment = display.attachment
            accessibilityLabel = display.filename

            switch display.attachment.kind {
            case .image:
                imageView.isHidden = false
                fileIconView.isHidden = true
                filenameLabel.isHidden = true
                if let image = display.thumbnailImage {
                    imageView.image = image
                    imageView.tintColor = nil
                    imageView.contentMode = .scaleAspectFill
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
            case .file:
                imageView.isHidden = true
                fileIconView.isHidden = false
                filenameLabel.isHidden = false
                filenameLabel.text = display.filename
            }
        }

        private func configure() {
            translatesAutoresizingMaskIntoConstraints = false
            layer.cornerRadius = Metrics.attachmentChipCornerRadius
            layer.cornerCurve = .continuous
            clipsToBounds = true
            backgroundColor = UIColor.white.withAlphaComponent(0.18)
            isAccessibilityElement = true
            accessibilityHint = String(localized: .generalOpensPreview)
            accessibilityTraits = .button

            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.clipsToBounds = true
            addSubview(imageView)

            fileIconView.translatesAutoresizingMaskIntoConstraints = false
            fileIconView.contentMode = .scaleAspectFit
            fileIconView.tintColor = .white
            fileIconView.image = UIImage(
                systemName: "doc.text.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: Metrics.fileIconPointSize,
                    weight: .semibold
                )
            )
            addSubview(fileIconView)

            filenameLabel.translatesAutoresizingMaskIntoConstraints = false
            filenameLabel.font = .systemFont(ofSize: Metrics.filenameFontSize, weight: .medium)
            filenameLabel.textColor = .white
            filenameLabel.textAlignment = .center
            filenameLabel.numberOfLines = 1
            filenameLabel.lineBreakMode = .byTruncatingMiddle
            addSubview(filenameLabel)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

                fileIconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                fileIconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4.0),

                filenameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3.0),
                filenameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3.0),
                filenameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4.0)
            ])
        }
    }
}
