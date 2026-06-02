//
//  ChatMarkdownMathBlockView.swift
//  UniLLMs
//
//  Displays a block LaTeX formula rendered from Markdown.
//  Created by OpenAI on 2026/5/14.
//

import UIKit

final class ChatMarkdownMathBlockView: UIView {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 10.0
        static let verticalPadding: CGFloat = 6.0
        static let cornerRadius: CGFloat = 7.0
    }

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let heightConstraint: NSLayoutConstraint
    private let imageWidthConstraint: NSLayoutConstraint
    private let imageHeightConstraint: NSLayoutConstraint

    init(
        mathBlock: ChatMarkdownMathBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        let renderedImage = ChatMarkdownMathImageRenderer.renderDisplay(
            latex: mathBlock.latex,
            font: style.bodyFont(compatibleWith: traitCollection),
            textColor: style.textColor,
            traitCollection: traitCollection
        )

        heightConstraint = scrollView.heightAnchor.constraint(
            equalToConstant: (renderedImage?.image.size.height ?? 0.0) + Metrics.verticalPadding * 2.0
        )
        imageWidthConstraint = imageView.widthAnchor.constraint(
            equalToConstant: renderedImage?.image.size.width ?? 0.0
        )
        imageHeightConstraint = imageView.heightAnchor.constraint(
            equalToConstant: renderedImage?.image.size.height ?? 0.0
        )

        super.init(frame: .zero)

        configure()
        imageView.image = renderedImage?.image
        accessibilityLabel = String(localized: .markdownFormulaFormat(mathBlock.latex))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.backgroundColor = .clear
        scrollView.layer.cornerRadius = 0
        scrollView.layer.masksToBounds = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        let fittingContentWidth = contentView.widthAnchor.constraint(
            equalTo: imageView.widthAnchor,
            constant: Metrics.horizontalPadding * 2.0
        )
        fittingContentWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalPadding),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.verticalPadding),
            heightConstraint,

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.widthAnchor.constraint(
                greaterThanOrEqualTo: imageView.widthAnchor,
                constant: Metrics.horizontalPadding * 2.0
            ),
            fittingContentWidth,

            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageWidthConstraint,
            imageHeightConstraint
        ])
    }
}
