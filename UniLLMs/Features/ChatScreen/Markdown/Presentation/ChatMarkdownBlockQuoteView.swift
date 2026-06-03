//
//  ChatMarkdownBlockQuoteView.swift
//  UniLLMs
//
//  UIKit presentation for block quotes that contain dedicated Markdown blocks.
//  Created by Codex on 2026/6/3.
//

import UIKit

final class ChatMarkdownBlockQuoteView: UIView {
    private enum Metrics {
        static let ruleWidth = ChatMarkdownBlockQuoteStyle.barWidth
        static let ruleLeading = ChatMarkdownBlockQuoteStyle.barLeading
        static let contentSpacing = max(
            0.0,
            ChatMarkdownBlockQuoteStyle.indentPerLevel
                - ChatMarkdownBlockQuoteStyle.barLeading
                - ChatMarkdownBlockQuoteStyle.barWidth
        )
        static let contentTopInset: CGFloat = 0.0
        static let contentBottomInset: CGFloat = 6.0
    }

    private var blockQuoteBlock: ChatMarkdownBlockQuoteBlock
    private let style: ChatMarkdownRenderStyle
    private let renderingTraitCollection: UITraitCollection
    private let contentRow = UIStackView()
    private let ruleView = UIView()
    private let contentStackView = UIStackView()
    private var childRecords: [ChatMarkdownRenderedBlockViewRecord] = []

    var onNeedsHeightUpdate: (() -> Void)?

    init(
        blockQuoteBlock: ChatMarkdownBlockQuoteBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        self.blockQuoteBlock = blockQuoteBlock
        self.style = style
        renderingTraitCollection = traitCollection
        super.init(frame: .zero)
        configure()
        renderChildren()
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

    func update(blockQuoteBlock: ChatMarkdownBlockQuoteBlock) {
        self.blockQuoteBlock = blockQuoteBlock
        childRecords = ChatMarkdownRenderedBlockViewReconciler.reconcile(
            blockQuoteBlock.children,
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

        contentRow.axis = .horizontal
        contentRow.alignment = .fill
        contentRow.spacing = Metrics.contentSpacing
        contentRow.isLayoutMarginsRelativeArrangement = true
        contentRow.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.contentTopInset,
            leading: Metrics.ruleLeading,
            bottom: Metrics.contentBottomInset,
            trailing: 0.0
        )
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentRow)

        NSLayoutConstraint.activate([
            contentRow.topAnchor.constraint(equalTo: topAnchor),
            contentRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentRow.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        ruleView.backgroundColor = ChatMarkdownBlockQuoteStyle.barColor
        ruleView.translatesAutoresizingMaskIntoConstraints = false
        contentRow.addArrangedSubview(ruleView)
        ruleView.widthAnchor.constraint(equalToConstant: Metrics.ruleWidth).isActive = true

        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = UIStackView.spacingUseSystem
        contentStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStackView.setContentHuggingPriority(.required, for: .vertical)
        contentRow.addArrangedSubview(contentStackView)
    }

    private func renderChildren() {
        childRecords = ChatMarkdownRenderedBlockViewReconciler.append(
            blockQuoteBlock.children,
            to: contentStackView,
            configuration: blockViewConfiguration
        )
    }

    private func fittingHeight(for width: CGFloat) -> CGFloat {
        let fittingWidth = max(1.0, width)
        let contentWidth = max(
            1.0,
            fittingWidth
                - contentRow.directionalLayoutMargins.leading
                - contentRow.directionalLayoutMargins.trailing
                - contentRow.spacing
                - Metrics.ruleWidth
        )
        let contentHeight = contentStackView.systemLayoutSizeFitting(
            CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return ceil(
            contentRow.directionalLayoutMargins.top
                + contentHeight
                + contentRow.directionalLayoutMargins.bottom
        )
    }

    private var blockViewConfiguration: ChatMarkdownRenderedBlockViewConfiguration {
        ChatMarkdownRenderedBlockViewConfiguration(
            style: style,
            traitCollection: renderingTraitCollection
        ) { [weak self] in
            self?.onNeedsHeightUpdate?()
        }
    }
}
