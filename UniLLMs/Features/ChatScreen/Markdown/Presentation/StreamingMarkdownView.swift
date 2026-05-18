//
//  StreamingMarkdownView.swift
//  UniLLMs
//
//  UIView that embeds MarkdownDisplayView for streamed assistant Markdown.
//  Created by Zayrick on 2026/5/12.
//

import MarkdownDisplayView
import UIKit

final class StreamingMarkdownView: UIView {
    private let markdownView = MarkdownViewTextKit()
    private var accumulatedMarkdown = ""
    private var isStreaming = false
    private var traitChangeRegistration: (any UITraitChangeRegistration)?
    var onNeedsHeightUpdate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        configureTraitObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
        configureTraitObservation()
    }

    func appendMarkdown(_ string: String) {
        guard !string.isEmpty else {
            return
        }

        let wasStreaming = isStreaming
        accumulatedMarkdown += string
        startStreamingIfNeeded()
        markdownView.appendStreamData(wasStreaming ? string : accumulatedMarkdown)
    }

    func setFinishedMarkdown(_ markdown: String) {
        resetMarkdown()
        accumulatedMarkdown = markdown
        markdownView.markdown = markdown
        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    func finishStreamingContent() {
        guard isStreaming else {
            setFinishedMarkdown(accumulatedMarkdown)
            return
        }

        isStreaming = false
        markdownView.endRealStreaming { [weak self] in
            guard let self else { return }
            self.invalidateIntrinsicContentSize()
            self.onNeedsHeightUpdate?()
        }
    }

    func resetMarkdown() {
        accumulatedMarkdown = ""
        isStreaming = false
        markdownView.resetForReuse()
        invalidateIntrinsicContentSize()
        onNeedsHeightUpdate?()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingWidth = max(1.0, size.width)
        let fittingHeight = markdownView.systemLayoutSizeFitting(
            CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        return CGSize(width: fittingWidth, height: ceil(max(0.0, fittingHeight)))
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: sizeThatFits(bounds.size).height)
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false

        markdownView.translatesAutoresizingMaskIntoConstraints = false
        markdownView.backgroundColor = .clear
        markdownView.enableTypewriterEffect = false
        markdownView.configuration = makeMarkdownConfiguration()
        markdownView.onHeightChange = { [weak self] _ in
            guard let self else { return }
            self.invalidateIntrinsicContentSize()
            self.onNeedsHeightUpdate?()
        }
        markdownView.onLinkTap = { url in
            guard UIApplication.shared.canOpenURL(url) else {
                return
            }
            UIApplication.shared.open(url)
        }

        addSubview(markdownView)

        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: topAnchor),
            markdownView.leadingAnchor.constraint(equalTo: leadingAnchor),
            markdownView.trailingAnchor.constraint(equalTo: trailingAnchor),
            markdownView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [
                UITraitUserInterfaceStyle.self,
                UITraitPreferredContentSizeCategory.self,
                UITraitDisplayScale.self
            ]
        ) { (view: StreamingMarkdownView, _) in
            view.markdownView.configuration = view.makeMarkdownConfiguration()
            view.invalidateIntrinsicContentSize()
            view.onNeedsHeightUpdate?()
        }
    }

    private func startStreamingIfNeeded() {
        guard !isStreaming else {
            return
        }

        markdownView.resetForReuse()
        markdownView.configuration = makeMarkdownConfiguration()
        markdownView.enableTypewriterEffect = false
        markdownView.beginRealStreaming(autoScrollBottom: false, useSmartBuffer: true)
        isStreaming = true
    }

    private func makeMarkdownConfiguration() -> MarkdownConfiguration {
        let style = ChatMarkdownRenderStyle.assistant
        var configuration = MarkdownConfiguration.default

        configuration.bodyFont = style.bodyFont(compatibleWith: traitCollection)
        configuration.h1Font = style.headingFont(level: 1, compatibleWith: traitCollection)
        configuration.h2Font = style.headingFont(level: 2, compatibleWith: traitCollection)
        configuration.h3Font = style.headingFont(level: 3, compatibleWith: traitCollection)
        configuration.h4Font = style.headingFont(level: 4, compatibleWith: traitCollection)
        configuration.h5Font = style.headingFont(level: 5, compatibleWith: traitCollection)
        configuration.h6Font = style.headingFont(level: 6, compatibleWith: traitCollection)
        configuration.codeFont = style.codeFont(compatibleWith: traitCollection)
        configuration.blockquoteFont = ChatMarkdownFontTraits.adding(
            .traitItalic,
            to: style.bodyFont(compatibleWith: traitCollection)
        )

        configuration.textColor = style.textColor
        configuration.headingColor = style.textColor
        configuration.linkColor = style.linkColor
        configuration.codeTextColor = style.codeTextColor
        configuration.codeBackgroundColor = style.codeBackgroundColor
        configuration.blockquoteTextColor = style.secondaryTextColor
        configuration.blockquoteBarColor = ChatMarkdownBlockQuoteStyle.barColor
        configuration.tableBorderColor = .separator
        configuration.tableHeaderBackgroundColor = .tertiarySystemFill
        configuration.tableRowBackgroundColor = .clear
        configuration.tableAlternateRowBackgroundColor = .secondarySystemFill
        configuration.horizontalRuleColor = style.dividerColor
        configuration.imagePlaceholderColor = .tertiarySystemFill
        configuration.footnoteColor = style.secondaryTextColor
        configuration.tocTextColor = style.linkColor

        configuration.paragraphSpacing = style.bodyParagraphSpacing(compatibleWith: traitCollection)
        configuration.headingSpacing = style.headingParagraphSpacingAfter(
            level: 2,
            compatibleWith: traitCollection
        )
        configuration.listIndent = 14.0
        configuration.codeBlockPadding = 10.0
        configuration.blockquoteIndent = ChatMarkdownBlockQuoteStyle.indentPerLevel
        configuration.imageMaxHeight = 360.0
        configuration.imagePlaceholderHeight = 150.0
        configuration.streamMinModuleLength = 10
        configuration.typewriterTextMode = .append
        configuration.typewriterHeightUpdateInterval = 20

        configuration.headingTopSpacing = style.headingParagraphSpacingBefore(
            level: 2,
            compatibleWith: traitCollection
        )
        configuration.headingBottomSpacing = style.headingParagraphSpacingAfter(
            level: 2,
            compatibleWith: traitCollection
        )
        configuration.paragraphTopSpacing = 0.0
        configuration.paragraphBottomSpacing = style.bodyParagraphSpacing(compatibleWith: traitCollection)

        configuration.latexAlignment = .center
        configuration.latexBackgroundColor = .clear
        configuration.latexPadding = 8.0

        configuration.blockquoteBackgroundColor = .clear
        configuration.blockquoteBarWidth = ChatMarkdownBlockQuoteStyle.barWidth
        configuration.blockquoteContentSpacing = 6.0
        configuration.blockquoteContentPadding = 8.0

        configuration.tableMinColumnWidth = ChatMarkdownTableLayoutMetrics.minColumnWidth
        configuration.tableMaxColumnWidth = ChatMarkdownTableLayoutMetrics.maxColumnWidth
        configuration.tableRowHeight = ChatMarkdownTableLayoutMetrics.minRowHeight
        configuration.tableCellPadding = ChatMarkdownTableLayoutMetrics.cellHorizontalPadding
        configuration.tableSeparatorHeight = 1.0 / max(traitCollection.displayScale, 1.0)

        configuration.listItemSpacing = style.listItemSpacing(compatibleWith: traitCollection)
        configuration.listMarkerMinWidth = 20.0
        configuration.listMarkerSpacing = 4.0
        configuration.listTopPadding = 0.0
        configuration.listBottomPadding = 0.0

        configuration.detailsSummaryFont = style.calloutFont(compatibleWith: traitCollection)
        configuration.detailsSummaryTextColor = style.linkColor
        configuration.detailsSummaryMinHeight = 34.0
        configuration.detailsContentPadding = 10.0
        configuration.detailsSpacing = 8.0

        configuration.streamingHapticFeedbackStyle = .none
        configuration.lineSpacing = MarkdownLineSpacingConfiguration(
            body: style.bodyLineSpacing(compatibleWith: traitCollection),
            heading: style.headingLineSpacing(level: 2, compatibleWith: traitCollection),
            quote: style.blockQuoteParagraphSpacing(compatibleWith: traitCollection),
            codeBlock: style.codeLineSpacing(compatibleWith: traitCollection)
        )

        return configuration
    }
}
