//
//  ChatMarkdownRenderer+Lists.swift
//  UniLLMs
//
//  List Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

private enum ListLayout {
    static let indent: CGFloat = 24.0
    static let markerMinWidth: CGFloat = 20.0
    static let markerSpacing: CGFloat = 6.0
    static let itemSpacing: CGFloat = 2.0
}

private enum ListMarker {
    case text(String)
    case symbol(name: String)
}

final class ChatMarkdownListState {
    fileprivate var depth = 0
    fileprivate var orderedCounters: [Int] = []
}

extension ChatMarkdownRenderer {
    mutating func renderUnorderedList(_ list: UnorderedList) -> NSMutableAttributedString {
        listState.depth += 1
        defer { listState.depth -= 1 }
        return renderListItems(list.listItems, isOrdered: false)
    }

    mutating func renderOrderedList(_ list: OrderedList) -> NSMutableAttributedString {
        listState.depth += 1
        listState.orderedCounters.append(Int(list.startIndex))
        defer {
            listState.orderedCounters.removeLast()
            listState.depth -= 1
        }

        return renderListItems(list.listItems, isOrdered: true)
    }

    private mutating func renderListItems<Items: Sequence>(
        _ items: Items,
        isOrdered: Bool
    ) -> NSMutableAttributedString where Items.Element == ListItem {
        let result = NSMutableAttributedString()
        let listItems = Array(items)
        var markers: [ListMarker] = []
        markers.reserveCapacity(listItems.count)
        for item in listItems {
            markers.append(marker(for: item, isOrdered: isOrdered))
        }

        let markerColumnWidth = max(
            ListLayout.markerMinWidth,
            markers.map { markerWidth($0, isOrdered: isOrdered) }.max() ?? 0.0
        )

        for (item, marker) in zip(listItems, markers) {
            result.append(
                renderListItem(
                    item,
                    marker: marker,
                    isOrdered: isOrdered,
                    markerColumnWidth: markerColumnWidth
                )
            )
        }

        if listState.depth == 1 {
            result.append(NSAttributedString(string: "\n"))
        }

        return result
    }

    private mutating func marker(for item: ListItem, isOrdered: Bool) -> ListMarker {
        if let checkbox = item.checkbox {
            if isOrdered {
                _ = advanceOrderedCounter()
            }
            return checkbox == .checked
                ? .symbol(name: "checkmark.square")
                : .symbol(name: "square")
        }

        if isOrdered {
            let current = advanceOrderedCounter()
            return .text("\(current).")
        }

        return .text("-")
    }

    private mutating func advanceOrderedCounter() -> Int {
        let current = listState.orderedCounters.last ?? 1
        if !listState.orderedCounters.isEmpty {
            listState.orderedCounters[listState.orderedCounters.count - 1] = current + 1
        }
        return current
    }

    private mutating func renderListItem(
        _ item: ListItem,
        marker: ListMarker,
        isOrdered: Bool,
        markerColumnWidth: CGFloat
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let leadingParagraph = markerAttributedString(marker, isOrdered: isOrdered)
        var didAppendLeadingParagraph = false
        var didAppendLeadingContent = false

        for child in item.children {
            if isListBlock(child) {
                if !didAppendLeadingParagraph {
                    appendListParagraph(
                        leadingParagraph,
                        marker: marker,
                        isOrdered: isOrdered,
                        markerColumnWidth: markerColumnWidth,
                        to: result
                    )
                    didAppendLeadingParagraph = true
                }
                result.append(renderBlock(child))
                continue
            }

            if let paragraph = child as? Paragraph {
                let paragraphText = renderInlineChildren(of: paragraph)
                trimTrailingNewlines(in: paragraphText)
                guard paragraphText.length > 0 else {
                    continue
                }

                if !didAppendLeadingParagraph && !didAppendLeadingContent {
                    leadingParagraph.append(paragraphText)
                    didAppendLeadingContent = true
                } else {
                    if !didAppendLeadingParagraph {
                        appendListParagraph(
                            leadingParagraph,
                            marker: marker,
                            isOrdered: isOrdered,
                            markerColumnWidth: markerColumnWidth,
                            to: result
                        )
                        didAppendLeadingParagraph = true
                    }
                    appendListContinuation(
                        paragraphText,
                        markerColumnWidth: markerColumnWidth,
                        to: result
                    )
                }
                continue
            }

            let childResult = renderBlock(child)
            trimTrailingNewlines(in: childResult)
            guard childResult.length > 0 else {
                continue
            }

            if !didAppendLeadingParagraph {
                appendListParagraph(
                    leadingParagraph,
                    marker: marker,
                    isOrdered: isOrdered,
                    markerColumnWidth: markerColumnWidth,
                    to: result
                )
                didAppendLeadingParagraph = true
            }
            appendListContinuation(
                childResult,
                markerColumnWidth: markerColumnWidth,
                to: result
            )
        }

        if !didAppendLeadingParagraph {
            appendListParagraph(
                leadingParagraph,
                marker: marker,
                isOrdered: isOrdered,
                markerColumnWidth: markerColumnWidth,
                to: result
            )
        }

        return result
    }

    private func isListBlock(_ markup: any Markup) -> Bool {
        markup is UnorderedList || markup is OrderedList
    }

    private func appendListParagraph(
        _ paragraph: NSMutableAttributedString,
        marker: ListMarker,
        isOrdered: Bool,
        markerColumnWidth: CGFloat,
        to result: NSMutableAttributedString
    ) {
        trimTrailingNewlines(in: paragraph)
        appendNewlineIfNeeded(to: paragraph)
        apply(
            [
                .paragraphStyle: listParagraphStyle(
                    marker: marker,
                    isOrdered: isOrdered,
                    markerColumnWidth: markerColumnWidth
                )
            ],
            to: paragraph
        )
        result.append(paragraph)
    }

    private func appendListContinuation(
        _ attributedString: NSMutableAttributedString,
        markerColumnWidth: CGFloat,
        to result: NSMutableAttributedString
    ) {
        trimTrailingNewlines(in: attributedString)
        appendNewlineIfNeeded(to: attributedString)
        applyListContinuationParagraphStyle(
            to: attributedString,
            markerColumnWidth: markerColumnWidth
        )
        result.append(attributedString)
    }

    private func listParagraphStyle(
        marker: ListMarker,
        isOrdered: Bool,
        markerColumnWidth: CGFloat
    ) -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let contentIndent = listContentIndent(markerColumnWidth: markerColumnWidth)
        let markerIndent = max(
            listBaseIndent,
            contentIndent - ListLayout.markerSpacing - markerWidth(marker, isOrdered: isOrdered)
        )

        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.firstLineHeadIndent = markerIndent
        paragraphStyle.headIndent = contentIndent
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .left, location: contentIndent)
        ]
        paragraphStyle.paragraphSpacing = ListLayout.itemSpacing
        return paragraphStyle
    }

    private func applyListContinuationParagraphStyle(
        to attributedString: NSMutableAttributedString,
        markerColumnWidth: CGFloat
    ) {
        offsetParagraphIndent(
            in: attributedString,
            by: listContentIndent(markerColumnWidth: markerColumnWidth)
        )
    }

    private var listBaseIndent: CGFloat {
        CGFloat(max(0, listState.depth - 1)) * ListLayout.indent
    }

    private func listContentIndent(markerColumnWidth: CGFloat) -> CGFloat {
        listBaseIndent + markerColumnWidth + ListLayout.markerSpacing
    }

    private func markerAttributedString(_ marker: ListMarker, isOrdered: Bool) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        switch marker {
        case let .text(text):
            result.append(NSAttributedString(string: text, attributes: bodyAttributes()))
            result.addAttribute(
                .font,
                value: listMarkerFont(isOrdered: isOrdered),
                range: NSRange(location: 0, length: (text as NSString).length)
            )
        case let .symbol(name):
            if let image = symbolImage(named: name) {
                let symbol = NSMutableAttributedString(attachment: NSTextAttachment(image: image))
                symbol.addAttributes(
                    bodyAttributes(),
                    range: NSRange(location: 0, length: symbol.length)
                )
                result.append(symbol)
            }
        }
        result.append(NSAttributedString(string: "\t", attributes: bodyAttributes()))
        return result
    }

    private func markerWidth(_ marker: ListMarker, isOrdered: Bool) -> CGFloat {
        switch marker {
        case let .text(text):
            return textMarkerWidth(text, isOrdered: isOrdered)
        case let .symbol(name):
            return symbolImage(named: name)?.size.width ?? 0.0
        }
    }

    private func textMarkerWidth(_ marker: String, isOrdered: Bool) -> CGFloat {
        ceil((marker as NSString).size(withAttributes: [.font: listMarkerFont(isOrdered: isOrdered)]).width)
    }

    private func listMarkerFont(isOrdered: Bool) -> UIFont {
        guard isOrdered else {
            return currentBodyFont()
        }

        return .monospacedDigitSystemFont(
            ofSize: currentBodyFont().pointSize,
            weight: .regular
        )
    }

    private func symbolImage(named name: String) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: currentBodyFont(), scale: .medium)
        return UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(
                currentTextColor.resolvedColor(with: traitCollection),
                renderingMode: .alwaysOriginal
            )
    }
}
