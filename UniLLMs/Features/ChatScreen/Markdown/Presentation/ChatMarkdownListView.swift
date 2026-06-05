//
//  ChatMarkdownListView.swift
//  UniLLMs
//
//  UIKit presentation for Markdown lists that contain nested rendered blocks.
//  Created by Codex on 2026/6/3.
//

import UIKit

final class ChatMarkdownListView: UIView {
    private enum Metrics {
        static let markerMinWidth: CGFloat = 20.0
        static let markerSpacing: CGFloat = 6.0
    }

    private var listBlock: ChatMarkdownListBlock
    private let style: ChatMarkdownRenderStyle
    private let renderingTraitCollection: UITraitCollection
    private let imageLoader: any ChatMarkdownImageLoading
    private let stackView = UIStackView()
    private var itemViews: [ChatMarkdownListItemView] = []
    private var markerColumnWidth: CGFloat

    var onNeedsHeightUpdate: (() -> Void)?

    init(
        listBlock: ChatMarkdownListBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection,
        imageLoader: any ChatMarkdownImageLoading = URLSessionChatMarkdownImageLoader()
    ) {
        self.listBlock = listBlock
        self.style = style
        renderingTraitCollection = traitCollection
        self.imageLoader = imageLoader
        markerColumnWidth = Self.markerColumnWidth(
            for: listBlock,
            style: style,
            traitCollection: traitCollection
        )
        super.init(frame: .zero)
        configure()
        renderItems()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: max(1.0, size.width), height: fittingHeight(for: size.width))
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        sizeThatFits(targetSize)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        sizeThatFits(targetSize)
    }

    func update(listBlock: ChatMarkdownListBlock) {
        self.listBlock = listBlock
        markerColumnWidth = Self.markerColumnWidth(
            for: listBlock,
            style: style,
            traitCollection: renderingTraitCollection
        )
        stackView.spacing = style.listItemSpacing(compatibleWith: renderingTraitCollection)

        if itemViews.count == listBlock.items.count {
            for (itemView, item) in zip(itemViews, listBlock.items) {
                itemView.update(
                    item: item,
                    markerColumnWidth: markerColumnWidth,
                    isOrdered: listBlock.isOrdered
                )
            }
        } else {
            ChatMarkdownRenderedBlockViewReconciler.removeAllArrangedSubviews(in: stackView)
            itemViews.removeAll()
            renderItems()
        }

        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onNeedsHeightUpdate?()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = style.listItemSpacing(compatibleWith: renderingTraitCollection)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func renderItems() {
        for item in listBlock.items {
            let itemView = ChatMarkdownListItemView(
                item: item,
                markerColumnWidth: markerColumnWidth,
                isOrdered: listBlock.isOrdered,
                style: style,
                traitCollection: renderingTraitCollection,
                imageLoader: imageLoader,
                onNeedsHeightUpdate: { [weak self] in
                    self?.onNeedsHeightUpdate?()
                }
            )
            itemViews.append(itemView)
            stackView.addArrangedSubview(itemView)
        }
    }

    private func fittingHeight(for width: CGFloat) -> CGFloat {
        let itemWidth = max(1.0, width)
        let itemHeights = itemViews.map {
            $0.sizeThatFits(CGSize(width: itemWidth, height: UIView.layoutFittingCompressedSize.height)).height
        }
        let spacing = stackView.spacing * CGFloat(max(0, itemHeights.count - 1))
        return ceil(itemHeights.reduce(0.0, +) + spacing)
    }

    private static func markerColumnWidth(
        for listBlock: ChatMarkdownListBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) -> CGFloat {
        max(
            Metrics.markerMinWidth,
            listBlock.items.map {
                markerWidth(
                    $0.marker,
                    isOrdered: listBlock.isOrdered,
                    style: style,
                    traitCollection: traitCollection
                )
            }.max() ?? 0.0
        )
    }

    fileprivate static func markerWidth(
        _ marker: ChatMarkdownListMarker,
        isOrdered: Bool,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) -> CGFloat {
        switch marker {
        case let .text(text):
            let font = markerFont(
                isOrdered: isOrdered,
                style: style,
                traitCollection: traitCollection
            )
            return ceil((text as NSString).size(withAttributes: [.font: font]).width)
        case let .checkbox(isChecked):
            return checkboxImage(
                isChecked: isChecked,
                style: style,
                traitCollection: traitCollection
            )?.size.width ?? 0.0
        }
    }

    fileprivate static func markerFont(
        isOrdered: Bool,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) -> UIFont {
        let bodyFont = style.bodyFont(compatibleWith: traitCollection)
        guard isOrdered else {
            return bodyFont
        }

        return .monospacedDigitSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
    }

    fileprivate static func checkboxImage(
        isChecked: Bool,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) -> UIImage? {
        let name = isChecked ? "checkmark.square" : "square"
        let configuration = UIImage.SymbolConfiguration(
            font: style.bodyFont(compatibleWith: traitCollection),
            scale: .medium
        )
        return UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(
                style.textColor.resolvedColor(with: traitCollection),
                renderingMode: .alwaysOriginal
            )
    }
}

private final class ChatMarkdownListItemView: UIView {
    private enum Metrics {
        static let markerSpacing: CGFloat = 6.0
    }

    private var item: ChatMarkdownListItemBlock
    private var markerColumnWidth: CGFloat
    private var isOrdered: Bool
    private let style: ChatMarkdownRenderStyle
    private let renderingTraitCollection: UITraitCollection
    private let rowStackView = UIStackView()
    private let markerContainerView = UIView()
    private let markerLabel = UILabel()
    private let checkboxImageView = UIImageView()
    private let contentStackView = UIStackView()
    private var markerWidthConstraint: NSLayoutConstraint?
    private var childRecords: [ChatMarkdownRenderedBlockViewRecord] = []
    private let imageLoader: any ChatMarkdownImageLoading
    private let onNeedsHeightUpdate: (() -> Void)?

    init(
        item: ChatMarkdownListItemBlock,
        markerColumnWidth: CGFloat,
        isOrdered: Bool,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection,
        imageLoader: any ChatMarkdownImageLoading,
        onNeedsHeightUpdate: (() -> Void)?
    ) {
        self.item = item
        self.markerColumnWidth = markerColumnWidth
        self.isOrdered = isOrdered
        self.style = style
        renderingTraitCollection = traitCollection
        self.imageLoader = imageLoader
        self.onNeedsHeightUpdate = onNeedsHeightUpdate
        super.init(frame: .zero)
        configure()
        renderChildren()
        updateMarker()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = max(1.0, size.width)
        let contentWidth = max(
            1.0,
            width - markerColumnWidth - Metrics.markerSpacing
        )
        let contentHeight = contentStackView.systemLayoutSizeFitting(
            CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let markerHeight = markerContainerView.systemLayoutSizeFitting(
            CGSize(width: markerColumnWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return CGSize(width: width, height: ceil(max(markerHeight, contentHeight)))
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        sizeThatFits(targetSize)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        sizeThatFits(targetSize)
    }

    func update(
        item: ChatMarkdownListItemBlock,
        markerColumnWidth: CGFloat,
        isOrdered: Bool
    ) {
        self.item = item
        self.markerColumnWidth = markerColumnWidth
        self.isOrdered = isOrdered
        markerWidthConstraint?.constant = markerColumnWidth
        updateMarker()
        childRecords = ChatMarkdownRenderedBlockViewReconciler.reconcile(
            item.children,
            records: childRecords,
            in: contentStackView,
            configuration: blockViewConfiguration
        )
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onNeedsHeightUpdate?()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)

        rowStackView.axis = .horizontal
        rowStackView.alignment = .fill
        rowStackView.spacing = Metrics.markerSpacing
        rowStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStackView)

        NSLayoutConstraint.activate([
            rowStackView.topAnchor.constraint(equalTo: topAnchor),
            rowStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        markerContainerView.translatesAutoresizingMaskIntoConstraints = false
        markerWidthConstraint = markerContainerView.widthAnchor.constraint(equalToConstant: markerColumnWidth)
        markerWidthConstraint?.isActive = true
        rowStackView.addArrangedSubview(markerContainerView)

        markerLabel.textAlignment = .right
        markerLabel.numberOfLines = 1
        markerLabel.adjustsFontForContentSizeCategory = true
        markerLabel.translatesAutoresizingMaskIntoConstraints = false
        markerContainerView.addSubview(markerLabel)

        checkboxImageView.contentMode = .scaleAspectFit
        checkboxImageView.translatesAutoresizingMaskIntoConstraints = false
        markerContainerView.addSubview(checkboxImageView)

        NSLayoutConstraint.activate([
            markerLabel.topAnchor.constraint(equalTo: markerContainerView.topAnchor),
            markerLabel.leadingAnchor.constraint(equalTo: markerContainerView.leadingAnchor),
            markerLabel.trailingAnchor.constraint(equalTo: markerContainerView.trailingAnchor),
            checkboxImageView.topAnchor.constraint(equalTo: markerContainerView.topAnchor),
            checkboxImageView.trailingAnchor.constraint(equalTo: markerContainerView.trailingAnchor)
        ])

        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = UIStackView.spacingUseSystem
        contentStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStackView.setContentHuggingPriority(.required, for: .vertical)
        rowStackView.addArrangedSubview(contentStackView)
    }

    private func renderChildren() {
        childRecords = ChatMarkdownRenderedBlockViewReconciler.append(
            item.children,
            to: contentStackView,
            configuration: blockViewConfiguration
        )
    }

    private func updateMarker() {
        switch item.marker {
        case let .text(text):
            markerLabel.isHidden = false
            checkboxImageView.isHidden = true
            markerLabel.text = text
            markerLabel.font = ChatMarkdownListView.markerFont(
                isOrdered: isOrdered,
                style: style,
                traitCollection: renderingTraitCollection
            )
            markerLabel.textColor = style.textColor
            accessibilityLabel = text
        case let .checkbox(isChecked):
            markerLabel.isHidden = true
            checkboxImageView.isHidden = false
            checkboxImageView.image = ChatMarkdownListView.checkboxImage(
                isChecked: isChecked,
                style: style,
                traitCollection: renderingTraitCollection
            )
            accessibilityLabel = isChecked
                ? String(localized: .markdownTaskChecked)
                : String(localized: .markdownTaskUnchecked)
        }
    }

    private var blockViewConfiguration: ChatMarkdownRenderedBlockViewConfiguration {
        ChatMarkdownRenderedBlockViewConfiguration(
            style: style,
            traitCollection: renderingTraitCollection,
            imageLoader: imageLoader
        ) { [weak self] in
            self?.onNeedsHeightUpdate?()
        }
    }
}
