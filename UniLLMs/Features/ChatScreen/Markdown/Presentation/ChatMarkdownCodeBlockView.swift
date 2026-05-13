//
//  ChatMarkdownCodeBlockView.swift
//  UniLLMs
//
//  UIKit block view for Markdown fenced code blocks.
//  Created by Codex on 2026/5/13.
//

import UIKit

final class ChatMarkdownCodeBlockView: UIView {
    private enum Metrics {
        static let topMargin: CGFloat = 4.0
        static let bottomMargin: CGFloat = 8.0
        static let cornerRadius: CGFloat = 18.0
        static let headerTopInset: CGFloat = 8.0
        static let headerHorizontalInset: CGFloat = 12.0
        static let headerBottomSpacing: CGFloat = 8.0
        static let codeVerticalInset: CGFloat = 9.0
        static let codeLeadingInset: CGFloat = 12.0
        static let codeTrailingInset: CGFloat = 14.0
        static let lineNumberLeadingInset: CGFloat = 10.0
        static let lineNumberTrailingInset: CGFloat = 9.0
        static let codeLineSpacing: CGFloat = 2.0
    }

    private let containerView = UIView()
    private let languageLabel = UILabel()
    private let codeViewport = UIView()
    private let scrollView = ChatMarkdownCodeScrollView()
    private let codeLabel = UILabel()
    private let lineNumberLabel = UILabel()

    private let style: ChatMarkdownRenderStyle
    private let displayLanguage: String
    private let codeAttributedText: NSAttributedString
    private let lineNumberAttributedText: NSAttributedString
    private let codeTextSize: CGSize
    private let lineNumberColumnWidth: CGFloat
    private let headerHeight: CGFloat

    init(
        codeBlock: ChatMarkdownCodeBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        self.style = style
        displayLanguage = codeBlock.displayLanguage

        let code = Self.normalizedDisplayCode(codeBlock.code)
        let lineCount = Self.lineCount(in: code)
        let codeFont = style.codeFont(compatibleWith: traitCollection)
        let lineNumberFont = UIFont.monospacedDigitSystemFont(
            ofSize: codeFont.pointSize,
            weight: .regular
        )
        let headerFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12.5, weight: .semibold),
            compatibleWith: traitCollection
        )
        let codeAttributes = Self.codeAttributes(
            font: codeFont,
            color: style.codeTextColor
        )
        let lineNumberAttributes = Self.lineNumberAttributes(
            font: lineNumberFont,
            color: style.secondaryTextColor.withAlphaComponent(0.72)
        )

        codeAttributedText = NSAttributedString(string: code, attributes: codeAttributes)
        lineNumberAttributedText = NSAttributedString(
            string: Self.lineNumberText(lineCount: lineCount),
            attributes: lineNumberAttributes
        )
        codeTextSize = Self.codeTextSize(for: codeAttributedText, font: codeFont)
        lineNumberColumnWidth = Self.lineNumberColumnWidth(
            lineCount: lineCount,
            attributes: lineNumberAttributes
        )
        headerHeight = ceil(headerFont.lineHeight)

        super.init(frame: .zero)
        configure(headerFont: headerFont)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: totalHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: max(1.0, size.width), height: totalHeight)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        sizeThatFits(targetSize)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = max(1.0, bounds.width)
        containerView.frame = CGRect(
            x: 0.0,
            y: Metrics.topMargin,
            width: width,
            height: containerHeight
        )

        languageLabel.frame = CGRect(
            x: Metrics.headerHorizontalInset,
            y: Metrics.headerTopInset,
            width: max(1.0, width - Metrics.headerHorizontalInset * 2.0),
            height: headerHeight
        )

        let codeViewportY = Metrics.headerTopInset + headerHeight + Metrics.headerBottomSpacing
        codeViewport.frame = CGRect(
            x: 0.0,
            y: codeViewportY,
            width: width,
            height: codeAreaHeight
        )

        let codeAreaX = lineNumberColumnWidth
        let codeAreaWidth = max(1.0, width - codeAreaX)

        scrollView.frame = CGRect(
            x: codeAreaX,
            y: 0.0,
            width: codeAreaWidth,
            height: codeAreaHeight
        )
        let contentWidth = max(
            codeAreaWidth,
            Metrics.codeLeadingInset + codeTextSize.width + Metrics.codeTrailingInset
        )
        scrollView.contentSize = CGSize(width: contentWidth, height: codeAreaHeight)
        scrollView.isScrollEnabled = contentWidth > codeAreaWidth + 0.5
        scrollView.alwaysBounceHorizontal = scrollView.isScrollEnabled

        codeLabel.frame = CGRect(
            x: Metrics.codeLeadingInset,
            y: Metrics.codeVerticalInset,
            width: max(1.0, codeTextSize.width),
            height: max(1.0, codeTextSize.height)
        )

        lineNumberLabel.frame = CGRect(
            x: Metrics.lineNumberLeadingInset,
            y: Metrics.codeVerticalInset,
            width: max(
                1.0,
                lineNumberColumnWidth - Metrics.lineNumberLeadingInset - Metrics.lineNumberTrailingInset
            ),
            height: max(1.0, codeTextSize.height)
        )

        clampHorizontalOffset()
    }

    private func configure(headerFont: UIFont) {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false

        containerView.clipsToBounds = true
        containerView.isOpaque = false
        containerView.layer.cornerCurve = .continuous
        containerView.layer.cornerRadius = Metrics.cornerRadius
        containerView.layer.borderWidth = 0.0
        containerView.backgroundColor = style.codeBlockBackgroundColor
        addSubview(containerView)

        languageLabel.text = displayLanguage
        languageLabel.font = headerFont
        languageLabel.textColor = style.secondaryTextColor
        languageLabel.adjustsFontForContentSizeCategory = true
        languageLabel.numberOfLines = 1
        languageLabel.lineBreakMode = .byTruncatingTail
        containerView.addSubview(languageLabel)

        codeViewport.clipsToBounds = true
        codeViewport.backgroundColor = .clear
        containerView.addSubview(codeViewport)

        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.accessibilityLabel = "\(displayLanguage) code"
        codeViewport.addSubview(scrollView)

        codeLabel.attributedText = codeAttributedText
        codeLabel.backgroundColor = .clear
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byClipping
        codeLabel.isAccessibilityElement = true
        codeLabel.accessibilityLabel = codeAttributedText.string
        scrollView.addSubview(codeLabel)

        lineNumberLabel.attributedText = lineNumberAttributedText
        lineNumberLabel.backgroundColor = .clear
        lineNumberLabel.numberOfLines = 0
        lineNumberLabel.lineBreakMode = .byClipping
        lineNumberLabel.textAlignment = .right
        lineNumberLabel.isAccessibilityElement = false
        codeViewport.addSubview(lineNumberLabel)
    }

    private func clampHorizontalOffset() {
        let maxOffsetX = max(0.0, scrollView.contentSize.width - scrollView.bounds.width)
        if scrollView.contentOffset.x > maxOffsetX {
            scrollView.contentOffset = CGPoint(x: maxOffsetX, y: scrollView.contentOffset.y)
        }
    }

    private var totalHeight: CGFloat {
        Metrics.topMargin + containerHeight + Metrics.bottomMargin
    }

    private var containerHeight: CGFloat {
        Metrics.headerTopInset + headerHeight + Metrics.headerBottomSpacing + codeAreaHeight
    }

    private var codeAreaHeight: CGFloat {
        Metrics.codeVerticalInset * 2.0 + codeTextSize.height
    }

    private static func normalizedDisplayCode(_ code: String) -> String {
        let normalizedCode = code
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalizedCode.isEmpty ? " " : normalizedCode
    }

    private static func lineCount(in code: String) -> Int {
        max(1, code.components(separatedBy: "\n").count)
    }

    private static func lineNumberText(lineCount: Int) -> String {
        (1...max(1, lineCount))
            .map(String.init)
            .joined(separator: "\n")
    }

    private static func codeAttributes(
        font: UIFont,
        color: UIColor
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineSpacing = Metrics.codeLineSpacing

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func lineNumberAttributes(
        font: UIFont,
        color: UIColor
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineSpacing = Metrics.codeLineSpacing

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func codeTextSize(for attributedText: NSAttributedString, font: UIFont) -> CGSize {
        let measuredSize = attributedText.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size

        return CGSize(
            width: max(1.0, ceil(measuredSize.width)),
            height: max(ceil(font.lineHeight), ceil(measuredSize.height))
        )
    }

    private static func lineNumberColumnWidth(
        lineCount: Int,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let digitCount = max(1, String(lineCount).count)
        let sample = String(repeating: "8", count: digitCount) as NSString
        let numberWidth = ceil(sample.size(withAttributes: attributes).width)

        return Metrics.lineNumberLeadingInset + numberWidth + Metrics.lineNumberTrailingInset
    }
}

private final class ChatMarkdownCodeScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        let velocity = panGestureRecognizer.velocity(in: self)
        return contentSize.width > bounds.width + 0.5 && abs(velocity.x) > abs(velocity.y)
    }
}
