//
//  ChatMarkdownTableView.swift
//  UniLLMs
//
//  UIKit block view for Markdown tables.
//  Created by Zayrick on 2026/5/12.
//

import UIKit

final class ChatMarkdownTableView: UIView {
    private var layout: ChatMarkdownTableLayout
    private let scrollView = ChatMarkdownTableScrollView()
    private var tableView: ChatMarkdownTableContentView
    private let style: ChatMarkdownRenderStyle
    private let traitCollectionForRendering: UITraitCollection

    init(
        tableData: ChatMarkdownTableData,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        self.style = style
        traitCollectionForRendering = traitCollection
        layout = ChatMarkdownTableLayout.makeLayout(for: tableData)
        tableView = ChatMarkdownTableContentView(
            tableData: tableData,
            layout: layout,
            style: style,
            traitCollection: traitCollection
        )
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuild the inner content view in place when streaming adds rows or
    /// adjusts existing ones. The outer scroll view, gestures, and any
    /// scroll-offset are preserved.
    func update(tableData: ChatMarkdownTableData) {
        let newLayout = ChatMarkdownTableLayout.makeLayout(for: tableData)
        layout = newLayout
        tableView.update(tableData: tableData, layout: newLayout)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: layout.contentSize.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: max(1.0, size.width), height: layout.contentSize.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    private func updateLayout() {
        let viewportSize = CGSize(width: max(1.0, bounds.width), height: max(1.0, bounds.height))
        scrollView.frame = CGRect(origin: .zero, size: viewportSize)
        scrollView.contentSize = CGSize(
            width: max(layout.contentSize.width, viewportSize.width),
            height: max(layout.contentSize.height, viewportSize.height)
        )
        scrollView.isScrollEnabled = layout.contentSize.width > viewportSize.width + 0.5
        scrollView.alwaysBounceHorizontal = scrollView.isScrollEnabled
        tableView.frame = CGRect(origin: .zero, size: layout.contentSize)

        let maxOffsetX = max(0.0, scrollView.contentSize.width - viewportSize.width)
        if scrollView.contentOffset.x > maxOffsetX {
            scrollView.contentOffset = CGPoint(x: maxOffsetX, y: scrollView.contentOffset.y)
        }
        tableView.setNeedsDisplay()
    }

    private func configure() {
        backgroundColor = .clear
        clipsToBounds = true
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.accessibilityLabel = "Markdown table"

        addSubview(scrollView)
        scrollView.addSubview(tableView)
    }
}

private final class ChatMarkdownTableContentView: UIView {
    private var tableData: ChatMarkdownTableData
    private var layout: ChatMarkdownTableLayout
    private let style: ChatMarkdownRenderStyle
    private let traitCollectionForRendering: UITraitCollection
    private var cellTextViews: [ChatMarkdownTextView] = []

    init(
        tableData: ChatMarkdownTableData,
        layout: ChatMarkdownTableLayout,
        style: ChatMarkdownRenderStyle,
        traitCollection: UITraitCollection
    ) {
        self.tableData = tableData
        self.layout = layout
        self.style = style
        traitCollectionForRendering = traitCollection
        super.init(frame: CGRect(origin: .zero, size: layout.contentSize))
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCellTextViews()
    }

    func update(tableData: ChatMarkdownTableData, layout: ChatMarkdownTableLayout) {
        self.tableData = tableData
        self.layout = layout
        frame.size = layout.contentSize
        reconcileCellTextViews()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let tableRect = CGRect(
            x: 0.0,
            y: ChatMarkdownTableLayoutMetrics.verticalMargin,
            width: layout.columnWidths.reduce(0.0, +),
            height: layout.rowHeights.reduce(0.0, +)
        )
        guard tableRect.width > 0.0, tableRect.height > 0.0 else {
            return
        }

        let clipPath = UIBezierPath(
            roundedRect: tableRect,
            cornerRadius: ChatMarkdownTableLayoutMetrics.cornerRadius
        )
        context.saveGState()
        clipPath.addClip()
        drawBackgrounds(in: tableRect, context: context)
        drawInnerGrid(in: tableRect, context: context)
        context.restoreGState()

        drawOuterBorder(in: tableRect)
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false

        reconcileCellTextViews()
    }

    private func reconcileCellTextViews() {
        let cells = flattenedCells()
        for index in cells.indices {
            let cell = cells[index].cell
            let textView: ChatMarkdownTextView
            if cellTextViews.indices.contains(index) {
                textView = cellTextViews[index]
                textView.replaceTailAttributedText(cell.attributedText)
            } else {
                textView = ChatMarkdownTextView(attributedText: cell.attributedText)
                textView.setMarkdownLineBreakMode(.byCharWrapping)
                textView.isAccessibilityElement = true
                addSubview(textView)
                cellTextViews.append(textView)
            }
            textView.accessibilityLabel = accessibilityLabel(
                for: cell,
                rowIndex: cells[index].rowIndex,
                columnIndex: cells[index].columnIndex
            )
        }

        while cellTextViews.count > cells.count {
            let textView = cellTextViews.removeLast()
            textView.removeFromSuperview()
        }
    }

    private func flattenedCells() -> [(cell: ChatMarkdownTableCell, rowIndex: Int, columnIndex: Int)] {
        var cells: [(cell: ChatMarkdownTableCell, rowIndex: Int, columnIndex: Int)] = []
        for (rowIndex, row) in tableData.rows.enumerated() {
            for (columnIndex, cell) in row.enumerated() {
                cells.append((cell, rowIndex, columnIndex))
            }
        }
        return cells
    }

    private func accessibilityLabel(
        for cell: ChatMarkdownTableCell,
        rowIndex: Int,
        columnIndex: Int
    ) -> String {
        let role = cell.isHeader ? "Header" : "Cell"
        let text = cell.accessibilityText.isEmpty ? "Empty" : cell.accessibilityText
        return "\(role), row \(rowIndex + 1), column \(columnIndex + 1), \(text)"
    }

    private func layoutCellTextViews() {
        var textViewIndex = 0
        var rowY = ChatMarkdownTableLayoutMetrics.verticalMargin
        for (rowIndex, rowHeight) in layout.rowHeights.enumerated() {
            guard tableData.rows.indices.contains(rowIndex) else {
                continue
            }

            let row = tableData.rows[rowIndex]
            var cellX: CGFloat = 0.0
            for (columnIndex, columnWidth) in layout.columnWidths.enumerated() {
                defer { cellX += columnWidth }
                guard row.indices.contains(columnIndex),
                      cellTextViews.indices.contains(textViewIndex) else {
                    continue
                }

                let textView = cellTextViews[textViewIndex]
                textViewIndex += 1
                textView.frame = CGRect(
                    x: cellX + ChatMarkdownTableLayoutMetrics.cellHorizontalPadding,
                    y: rowY + ChatMarkdownTableLayoutMetrics.cellVerticalPadding,
                    width: max(
                        1.0,
                        columnWidth - ChatMarkdownTableLayoutMetrics.cellHorizontalPadding * 2.0
                    ),
                    height: max(
                        1.0,
                        rowHeight - ChatMarkdownTableLayoutMetrics.cellVerticalPadding * 2.0
                    )
                ).integral
            }

            rowY += rowHeight
        }
    }

    private func drawBackgrounds(in tableRect: CGRect, context: CGContext) {
        rowBackgroundColor.setFill()
        context.fill(tableRect)

        var rowY = tableRect.minY
        for (rowIndex, rowHeight) in layout.rowHeights.enumerated() {
            let rowRect = CGRect(
                x: tableRect.minX,
                y: rowY,
                width: tableRect.width,
                height: rowHeight
            )

            if rowIndex == 0 {
                headerBackgroundColor.setFill()
                context.fill(rowRect)
            } else if rowIndex.isMultiple(of: 2) {
                alternateRowBackgroundColor.setFill()
                context.fill(rowRect)
            }

            rowY += rowHeight
        }
    }

    private func drawInnerGrid(in tableRect: CGRect, context: CGContext) {
        context.setLineWidth(lineWidth)
        context.setStrokeColor(borderColor.cgColor)

        var rowY = tableRect.minY
        for rowHeight in layout.rowHeights.dropLast() {
            rowY += rowHeight
            let y = pixelAligned(rowY)
            context.move(to: CGPoint(x: tableRect.minX, y: y))
            context.addLine(to: CGPoint(x: tableRect.maxX, y: y))
        }

        var columnX = tableRect.minX
        for columnWidth in layout.columnWidths.dropLast() {
            columnX += columnWidth
            let x = pixelAligned(columnX)
            context.move(to: CGPoint(x: x, y: tableRect.minY))
            context.addLine(to: CGPoint(x: x, y: tableRect.maxY))
        }

        context.strokePath()
    }

    private func drawOuterBorder(in tableRect: CGRect) {
        let borderRect = tableRect.insetBy(dx: lineWidth / 2.0, dy: lineWidth / 2.0)
        let borderRadius = max(0.0, ChatMarkdownTableLayoutMetrics.cornerRadius - lineWidth / 2.0)
        let borderPath = UIBezierPath(roundedRect: borderRect, cornerRadius: borderRadius)
        borderPath.lineWidth = lineWidth
        borderColor.setStroke()
        borderPath.stroke()
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        (floor(value * displayScale) + 0.5) / displayScale
    }

    private var displayScale: CGFloat {
        let scale = traitCollectionForRendering.displayScale
        return scale > 0.0 ? scale : 1.0
    }

    private var lineWidth: CGFloat {
        1.0 / displayScale
    }

    private var borderColor: UIColor {
        UIColor.separator.withAlphaComponent(0.55).resolvedColor(with: traitCollectionForRendering)
    }

    private var headerBackgroundColor: UIColor {
        style.codeBackgroundColor.resolvedColor(with: traitCollectionForRendering)
    }

    private var rowBackgroundColor: UIColor {
        UIColor.systemBackground.withAlphaComponent(0.08).resolvedColor(with: traitCollectionForRendering)
    }

    private var alternateRowBackgroundColor: UIColor {
        UIColor.tertiarySystemFill.resolvedColor(with: traitCollectionForRendering)
    }
}

private final class ChatMarkdownTableScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        let velocity = panGestureRecognizer.velocity(in: self)
        return contentSize.width > bounds.width + 0.5 && abs(velocity.x) > abs(velocity.y)
    }
}
