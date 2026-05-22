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
        static let lineNumberHorizontalInset: CGFloat = 10.0
    }

    private let containerView = UIView()
    private let languageLabel = UILabel()
    private let codeViewport = UIView()
    private let scrollView = ChatMarkdownCodeScrollView()
    private let codeContentView = ChatMarkdownCodeContentView()
    private let lineNumberView = ChatMarkdownCodeLineNumberView()

    private let style: ChatMarkdownRenderStyle
    private var displayLanguage: String
    private var codeText: String
    private var isStreaming: Bool
    private var codeLines: [String]
    private var codeTextSize: CGSize
    private var lineNumberColumnWidth: CGFloat
    private var headerHeight: CGFloat
    private var codeFont: UIFont
    private var headerFont: UIFont
    private var codeLineSpacing: CGFloat
    private var codeTextColor: UIColor
    private var lineNumberTextColor: UIColor
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    init(
        codeBlock: ChatMarkdownCodeBlock,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        let initialCodeText = Self.normalizedDisplayCode(codeBlock.code)
        let initialCodeLines = Self.codeLines(in: initialCodeText)
        let initialCodeFont = style.codeFont(compatibleWith: traitCollection)
        let initialCodeLineSpacing = style.codeLineSpacing(compatibleWith: traitCollection)
        let initialHeaderFont = ChatMarkdownFontTraits.adding(
            .traitBold,
            to: UIFont.preferredFont(
                forTextStyle: .caption1,
                compatibleWith: traitCollection
            )
        )

        self.style = style
        displayLanguage = codeBlock.displayLanguage
        codeText = initialCodeText
        isStreaming = codeBlock.isStreaming
        codeLines = initialCodeLines
        codeFont = initialCodeFont
        codeLineSpacing = initialCodeLineSpacing
        codeTextColor = style.codeTextColor
        lineNumberTextColor = style.secondaryTextColor.withAlphaComponent(0.72)
        headerFont = initialHeaderFont
        codeTextSize = Self.codeTextSize(
            for: initialCodeLines,
            font: initialCodeFont,
            lineSpacing: initialCodeLineSpacing
        )
        lineNumberColumnWidth = Self.lineNumberColumnWidth(
            lineCount: initialCodeLines.count,
            font: initialCodeFont
        )
        headerHeight = ceil(initialHeaderFont.lineHeight)

        super.init(frame: .zero)
        configure(headerFont: headerFont)
        configureTraitObservation()
    }

    /// Replace the code body and (optionally) the language without recreating
    /// the whole block. The code and line number columns share one row model so
    /// every line number is positioned from the same y-origin as its code row.
    func update(codeBlock: ChatMarkdownCodeBlock) {
        let newLanguage = codeBlock.displayLanguage
        if newLanguage != displayLanguage {
            displayLanguage = newLanguage
            languageLabel.text = newLanguage
            updateCodeAccessibilityLabel()
        }

        if codeBlock.isStreaming != isStreaming {
            isStreaming = codeBlock.isStreaming
            updateCodeAccessibilityLabel()
        }

        let newCodeText = Self.normalizedDisplayCode(codeBlock.code)
        guard newCodeText != codeText else {
            return
        }

        codeText = newCodeText
        codeLines = Self.codeLines(in: newCodeText)
        codeTextSize = Self.codeTextSize(
            for: codeLines,
            font: codeFont,
            lineSpacing: codeLineSpacing
        )
        lineNumberColumnWidth = Self.lineNumberColumnWidth(
            lineCount: codeLines.count,
            font: codeFont
        )

        codeContentView.update(
            lines: codeLines,
            font: codeFont,
            textColor: codeTextColor,
            lineSpacing: codeLineSpacing
        )
        codeContentView.accessibilityLabel = codeAccessibilityText
        lineNumberView.update(
            lineCount: codeLines.count,
            font: codeFont,
            textColor: lineNumberTextColor,
            lineSpacing: codeLineSpacing
        )

        invalidateIntrinsicContentSize()
        setNeedsLayout()
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

        codeContentView.frame = CGRect(
            x: Metrics.codeLeadingInset,
            y: Metrics.codeVerticalInset,
            width: max(1.0, codeTextSize.width),
            height: max(1.0, codeTextSize.height)
        )

        lineNumberView.frame = CGRect(
            x: 0.0,
            y: Metrics.codeVerticalInset,
            width: max(1.0, lineNumberColumnWidth),
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
        updateCodeAccessibilityLabel()
        codeViewport.addSubview(scrollView)

        codeContentView.update(
            lines: codeLines,
            font: codeFont,
            textColor: codeTextColor,
            lineSpacing: codeLineSpacing
        )
        codeContentView.isAccessibilityElement = true
        codeContentView.accessibilityLabel = codeAccessibilityText
        codeContentView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Copy Code",
                target: self,
                selector: #selector(copyCodeFromAccessibilityAction(_:))
            )
        ]
        scrollView.addSubview(codeContentView)

        lineNumberView.update(
            lineCount: codeLines.count,
            font: codeFont,
            textColor: lineNumberTextColor,
            lineSpacing: codeLineSpacing
        )
        lineNumberView.isAccessibilityElement = false
        codeViewport.addSubview(lineNumberView)
    }

    private func updateCodeAccessibilityLabel() {
        let label = isStreaming
            ? "\(displayLanguage) code, streaming"
            : "\(displayLanguage) code"
        scrollView.accessibilityLabel = label
        codeContentView.accessibilityHint = isStreaming ? "Streaming" : nil
    }

    @objc private func copyCodeFromAccessibilityAction(_ action: UIAccessibilityCustomAction) -> Bool {
        UIPasteboard.general.string = codeText
        return true
    }

    private func configureTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [
                UITraitUserInterfaceStyle.self,
                UITraitPreferredContentSizeCategory.self,
                UITraitDisplayScale.self
            ]
        ) { (view: ChatMarkdownCodeBlockView, _) in
            view.updateResolvedStyle(compatibleWith: view.traitCollection)
        }
    }

    private func updateResolvedStyle(compatibleWith traitCollection: UITraitCollection) {
        codeFont = style.codeFont(compatibleWith: traitCollection)
        codeLineSpacing = style.codeLineSpacing(compatibleWith: traitCollection)
        headerFont = ChatMarkdownFontTraits.adding(
            .traitBold,
            to: UIFont.preferredFont(
                forTextStyle: .caption1,
                compatibleWith: traitCollection
            )
        )
        headerHeight = ceil(headerFont.lineHeight)
        codeTextColor = style.codeTextColor
        lineNumberTextColor = style.secondaryTextColor.withAlphaComponent(0.72)
        codeTextSize = Self.codeTextSize(
            for: codeLines,
            font: codeFont,
            lineSpacing: codeLineSpacing
        )
        lineNumberColumnWidth = Self.lineNumberColumnWidth(
            lineCount: codeLines.count,
            font: codeFont
        )

        containerView.backgroundColor = style.codeBlockBackgroundColor
        languageLabel.font = headerFont
        languageLabel.textColor = style.secondaryTextColor
        codeContentView.update(
            lines: codeLines,
            font: codeFont,
            textColor: codeTextColor,
            lineSpacing: codeLineSpacing
        )
        lineNumberView.update(
            lineCount: codeLines.count,
            font: codeFont,
            textColor: lineNumberTextColor,
            lineSpacing: codeLineSpacing
        )

        invalidateIntrinsicContentSize()
        setNeedsLayout()
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
        code
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private var codeAccessibilityText: String {
        codeText.isEmpty ? "Empty code block" : codeText
    }

    private static func codeLines(in code: String) -> [String] {
        let lines = code.components(separatedBy: "\n")
        return lines.isEmpty ? [" "] : lines
    }

    private static func codeTextSize(
        for lines: [String],
        font: UIFont,
        lineSpacing: CGFloat
    ) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let maxLineWidth = lines
            .map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
            .max() ?? 1.0
        let height = ChatMarkdownCodeLineLayout.contentHeight(
            lineCount: lines.count,
            font: font,
            lineSpacing: lineSpacing
        )

        return CGSize(width: max(1.0, maxLineWidth), height: height)
    }

    private static func lineNumberColumnWidth(
        lineCount: Int,
        font: UIFont
    ) -> CGFloat {
        let digitCount = max(1, String(max(1, lineCount)).count)
        let sample = String(repeating: "8", count: digitCount) as NSString
        let numberWidth = ceil(sample.size(withAttributes: [.font: font]).width)

        return Metrics.lineNumberHorizontalInset * 2.0 + numberWidth
    }
}

private enum ChatMarkdownCodeLineLayout {
    static func lineAdvance(font: UIFont, lineSpacing: CGFloat) -> CGFloat {
        font.lineHeight + lineSpacing
    }

    static func lineOriginY(
        lineIndex: Int,
        font: UIFont,
        lineSpacing: CGFloat
    ) -> CGFloat {
        CGFloat(lineIndex) * lineAdvance(font: font, lineSpacing: lineSpacing)
    }

    static func contentHeight(
        lineCount: Int,
        font: UIFont,
        lineSpacing: CGFloat
    ) -> CGFloat {
        let normalizedLineCount = max(1, lineCount)
        let textHeight = CGFloat(normalizedLineCount) * font.lineHeight
        let spacingHeight = CGFloat(normalizedLineCount - 1) * lineSpacing
        return max(ceil(font.lineHeight), ceil(textHeight + spacingHeight))
    }

    static func visibleLineRange(
        in rect: CGRect,
        lineCount: Int,
        font: UIFont,
        lineSpacing: CGFloat
    ) -> ClosedRange<Int>? {
        let normalizedLineCount = max(1, lineCount)
        let advance = lineAdvance(font: font, lineSpacing: lineSpacing)
        guard advance > 0.0 else {
            return nil
        }

        let firstLine = max(0, Int(floor(rect.minY / advance)))
        let lastLine = min(normalizedLineCount - 1, Int(ceil(rect.maxY / advance)))
        guard firstLine <= lastLine else {
            return nil
        }

        return firstLine...lastLine
    }
}

private final class ChatMarkdownCodeContentView: UIView {
    private var lines: [String] = [" "]
    private var font: UIFont = .monospacedSystemFont(ofSize: 14.0, weight: .regular)
    private var textColor: UIColor = .label
    private var lineSpacing: CGFloat = 0.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        lines: [String],
        font: UIFont,
        textColor: UIColor,
        lineSpacing: CGFloat
    ) {
        self.lines = lines.isEmpty ? [" "] : lines
        self.font = font
        self.textColor = textColor
        self.lineSpacing = lineSpacing
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let visibleLines = ChatMarkdownCodeLineLayout.visibleLineRange(
            in: rect,
            lineCount: lines.count,
            font: font,
            lineSpacing: lineSpacing
        ) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        for lineIndex in visibleLines {
            let line = lines[lineIndex] as NSString
            let y = ChatMarkdownCodeLineLayout.lineOriginY(
                lineIndex: lineIndex,
                font: font,
                lineSpacing: lineSpacing
            )
            line.draw(at: CGPoint(x: 0.0, y: y), withAttributes: attributes)
        }
    }
}

private final class ChatMarkdownCodeLineNumberView: UIView {
    private var lineCount: Int = 1
    private var font: UIFont = .monospacedSystemFont(ofSize: 14.0, weight: .regular)
    private var textColor: UIColor = .secondaryLabel
    private var lineSpacing: CGFloat = 0.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        lineCount: Int,
        font: UIFont,
        textColor: UIColor,
        lineSpacing: CGFloat
    ) {
        self.lineCount = max(1, lineCount)
        self.font = font
        self.textColor = textColor
        self.lineSpacing = lineSpacing
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let visibleLines = ChatMarkdownCodeLineLayout.visibleLineRange(
            in: rect,
            lineCount: lineCount,
            font: font,
            lineSpacing: lineSpacing
        ) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        for lineIndex in visibleLines {
            let numberText = "\(lineIndex + 1)" as NSString
            let numberSize = numberText.size(withAttributes: attributes)
            let x = floor((bounds.width - numberSize.width) * 0.5)
            let y = ChatMarkdownCodeLineLayout.lineOriginY(
                lineIndex: lineIndex,
                font: font,
                lineSpacing: lineSpacing
            )
            numberText.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        }
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
