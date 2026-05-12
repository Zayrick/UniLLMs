//
//  ChatMarkdownRenderer+Inline.swift
//  UniLLMs
//
//  Inline Markdown rendering.
//  Created by Zayrick on 2026/5/12.
//

import Markdown
import UIKit

extension ChatMarkdownRenderer {
    mutating func renderInlineChildren(of markup: any Markup) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(renderInline(child))
        }
        return result
    }

    private mutating func renderInline(_ markup: any Markup) -> NSMutableAttributedString {
        switch markup {
        case let text as Text:
            return NSMutableAttributedString(string: text.string, attributes: bodyAttributes())
        case let strong as Strong:
            let result = renderInlineChildren(of: strong)
            apply([.font: boldFont(from: currentBodyFont())], to: result)
            return result
        case let emphasis as Emphasis:
            let result = renderInlineChildren(of: emphasis)
            apply([.font: italicFont(from: currentBodyFont())], to: result)
            return result
        case let strikethrough as Strikethrough:
            let result = renderInlineChildren(of: strikethrough)
            apply([.strikethroughStyle: NSUnderlineStyle.single.rawValue], to: result)
            return result
        case let inlineCode as InlineCode:
            return NSMutableAttributedString(
                string: inlineCode.code,
                attributes: [
                    .font: style.codeFont(compatibleWith: traitCollection),
                    .foregroundColor: style.codeTextColor,
                    .backgroundColor: style.codeBackgroundColor
                ]
            )
        case let link as Link:
            let result = renderInlineChildren(of: link)
            apply(
                [
                    .foregroundColor: style.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                to: result
            )
            if let destination = link.destination,
               let url = URL(string: destination) {
                apply([.link: url], to: result)
            }
            return result
        case let image as Markdown.Image:
            return NSMutableAttributedString(
                string: imageDisplayText(source: image.source, altText: image.plainText),
                attributes: secondaryAttributes()
            )
        case _ as SoftBreak:
            return NSMutableAttributedString(string: " ", attributes: bodyAttributes())
        case _ as LineBreak:
            return NSMutableAttributedString(string: "\n", attributes: bodyAttributes())
        case let html as InlineHTML:
            return NSMutableAttributedString(string: html.rawHTML, attributes: secondaryAttributes())
        case let unorderedList as UnorderedList:
            return renderUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            return renderOrderedList(orderedList)
        case let paragraph as Paragraph:
            return renderParagraph(paragraph)
        default:
            return renderInlineChildren(of: markup)
        }
    }

    private func boldFont(from font: UIFont) -> UIFont {
        font.withSymbolicTraits(.traitBold) ?? .boldSystemFont(ofSize: font.pointSize)
    }

    private func italicFont(from font: UIFont) -> UIFont {
        font.withSymbolicTraits(.traitItalic) ?? .italicSystemFont(ofSize: font.pointSize)
    }

    func imageDisplayText(source: String?, altText: String) -> String {
        let label = altText.isEmpty ? "Image" : altText
        guard let source,
              !source.isEmpty else {
            return "[\(label)]"
        }

        return "[\(label): \(source)]"
    }
}

private extension UIFont {
    func withSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return nil
        }

        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
