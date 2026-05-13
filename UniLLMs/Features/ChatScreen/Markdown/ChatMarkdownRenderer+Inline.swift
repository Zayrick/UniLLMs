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
        let children = Array(markup.children)

        for (index, child) in children.enumerated() {
            if let inlineCode = child as? InlineCode {
                result.append(
                    renderInlineCode(
                        inlineCode,
                        needsLeadingMargin: needsInlineCodeMargin(before: result.string.last),
                        needsTrailingMargin: needsInlineCodeMargin(
                            after: firstVisibleCharacter(after: index, in: children)
                        )
                    )
                )
            } else {
                result.append(renderInline(child))
            }
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
            return renderInlineCode(
                inlineCode,
                needsLeadingMargin: false,
                needsTrailingMargin: false
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

    private func renderInlineCode(
        _ inlineCode: InlineCode,
        needsLeadingMargin: Bool,
        needsTrailingMargin: Bool
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let bodyAttrs = bodyAttributes()

        if needsLeadingMargin {
            result.append(
                NSAttributedString(
                    string: ChatMarkdownInlineCodeStyle.outerMargin,
                    attributes: bodyAttrs
                )
            )
        }

        result.append(
            NSAttributedString(
                string: inlineCode.code,
                attributes: [
                    .font: style.codeFont(compatibleWith: traitCollection),
                    .foregroundColor: style.codeTextColor,
                    .chatInlineCodeBackgroundColor: style.codeBackgroundColor,
                    .chatInlineCodeCornerRadius: ChatMarkdownInlineCodeStyle.cornerRadius
                ]
            )
        )

        if needsTrailingMargin {
            result.append(
                NSAttributedString(
                    string: ChatMarkdownInlineCodeStyle.outerMargin,
                    attributes: bodyAttrs
                )
            )
        }

        return result
    }

    private func needsInlineCodeMargin(before character: Character?) -> Bool {
        guard let character else {
            return false
        }

        return !isInlineCodeMarginBoundary(character)
    }

    private func needsInlineCodeMargin(after character: Character?) -> Bool {
        guard let character else {
            return false
        }

        return !isInlineCodeMarginBoundary(character)
    }

    private func isInlineCodeMarginBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private func firstVisibleCharacter(after index: Int, in children: [any Markup]) -> Character? {
        guard index + 1 < children.count else {
            return nil
        }

        for child in children[(index + 1)...] {
            if let character = visibleText(in: child).first {
                return character
            }
        }

        return nil
    }

    private func visibleText(in markup: any Markup) -> String {
        switch markup {
        case let text as Text:
            return text.string
        case let inlineCode as InlineCode:
            return inlineCode.code
        case let image as Markdown.Image:
            return imageDisplayText(source: image.source, altText: image.plainText)
        case _ as SoftBreak:
            return " "
        case _ as LineBreak:
            return "\n"
        case let html as InlineHTML:
            return html.rawHTML
        default:
            var result = ""
            for child in markup.children {
                result += visibleText(in: child)
            }
            return result
        }
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
