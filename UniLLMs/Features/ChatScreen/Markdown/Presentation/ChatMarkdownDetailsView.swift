//
//  ChatMarkdownDetailsView.swift
//  UniLLMs
//
//  UIKit presentation for GitHub-style HTML details blocks.
//  Created by Codex on 2026/5/14.
//

import UIKit

final class ChatMarkdownDetailsView: UIView {
    private enum Metrics {
        static let ruleWidth = ChatMarkdownBlockQuoteStyle.barWidth
        static let ruleLeading = ChatMarkdownBlockQuoteStyle.barLeading
        static let contentSpacing = ChatMarkdownBlockQuoteStyle.indentPerLevel
            - ChatMarkdownBlockQuoteStyle.barLeading
            - ChatMarkdownBlockQuoteStyle.barWidth
        static let contentTopInset: CGFloat = 2.0
        static let contentBottomInset: CGFloat = 6.0
    }

    private var detailsBlock: ChatMarkdownDetailsBlock
    private let style: ChatMarkdownRenderStyle
    private let renderingTraitCollection: UITraitCollection
    private let stackView = UIStackView()
    private let summaryButton = UIButton(type: .system)
    private let contentRow = UIStackView()
    private let contentStackView = UIStackView()
    private let ruleView = UIView()
    private var childRecords: [ChatMarkdownRenderedBlockViewRecord] = []
    private var isExpanded: Bool

    var onNeedsHeightUpdate: (() -> Void)?

    init(
        detailsBlock: ChatMarkdownDetailsBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        self.detailsBlock = detailsBlock
        self.style = style
        renderingTraitCollection = traitCollection
        isExpanded = detailsBlock.isOpen
        super.init(frame: .zero)
        configure()
        renderChildren()
        updateExpandedState(animated: false)
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

    func update(detailsBlock: ChatMarkdownDetailsBlock) {
        self.detailsBlock = detailsBlock
        summaryButton.accessibilityLabel = detailsBlock.summary
        childRecords = ChatMarkdownRenderedBlockViewReconciler.reconcile(
            detailsBlock.children,
            records: childRecords,
            in: contentStackView,
            configuration: blockViewConfiguration
        )
        updateSummaryButton()
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
        stackView.spacing = 0.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        summaryButton.contentHorizontalAlignment = .leading
        summaryButton.titleLabel?.font = style.bodyFont(compatibleWith: renderingTraitCollection)
        summaryButton.titleLabel?.numberOfLines = 0
        summaryButton.accessibilityLabel = detailsBlock.summary
        summaryButton.addAction(
            UIAction { [weak self] _ in
                self?.toggleExpanded()
            },
            for: .primaryActionTriggered
        )
        stackView.addArrangedSubview(summaryButton)

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
        stackView.addArrangedSubview(contentRow)

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

        updateSummaryButton()
    }

    private func renderChildren() {
        childRecords = ChatMarkdownRenderedBlockViewReconciler.append(
            detailsBlock.children,
            to: contentStackView,
            configuration: blockViewConfiguration
        )
    }

    private func toggleExpanded() {
        isExpanded.toggle()
        updateExpandedState(animated: true)
    }

    private func updateExpandedState(animated: Bool) {
        contentRow.isHidden = !isExpanded
        updateSummaryButton()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onNeedsHeightUpdate?()

        guard animated else {
            return
        }

        UIView.animate(withDuration: 0.18) {
            self.superview?.layoutIfNeeded()
        }
    }

    private func updateSummaryButton() {
        let summaryFont = style.bodyFont(compatibleWith: renderingTraitCollection)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: isExpanded ? "chevron.down" : "chevron.right")
        configuration.imagePadding = 6.0
        configuration.title = detailsBlock.summary
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = summaryFont
            return outgoing
        }
        configuration.baseForegroundColor = style.linkColor
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 5.0,
            leading: 0.0,
            bottom: 5.0,
            trailing: 0.0
        )
        summaryButton.configuration = configuration
        summaryButton.accessibilityValue = isExpanded ? "Expanded" : "Collapsed"
    }

    private func fittingHeight(for width: CGFloat) -> CGFloat {
        let fittingWidth = max(1.0, width)
        let summaryHeight = summaryButton.systemLayoutSizeFitting(
            CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        guard isExpanded else {
            return ceil(summaryHeight)
        }

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
        let rowHeight = contentRow.directionalLayoutMargins.top
            + contentHeight
            + contentRow.directionalLayoutMargins.bottom

        return ceil(summaryHeight + rowHeight)
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
