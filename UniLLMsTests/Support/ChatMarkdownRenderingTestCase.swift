//
//  ChatMarkdownRenderingTestCase.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

class ChatMarkdownRenderingTestCase: XCTestCase {
    var markdownRendererTraits: UITraitCollection {
        UITraitCollection { traits in
            traits.displayScale = 2.0
            traits.preferredContentSizeCategory = .large
        }
    }

    func renderMarkdownText(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> NSAttributedString {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: markdown)
        let result = NSMutableAttributedString()

        for block in blocks {
            switch block {
            case let .text(text):
                result.append(text)
            case .codeBlock:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .mathBlock:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .table:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .image:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            case .details:
                XCTFail("Expected Markdown to render only text blocks.", file: file, line: line)
            }
        }

        return result
    }
}

extension NSAttributedString {
    var containsTextAttachment: Bool {
        textAttachmentCount > 0
    }

    var textAttachmentCount: Int {
        var attachmentCount = 0
        enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: length)
        ) { value, _, _ in
            guard value is NSTextAttachment else {
                return
            }

            attachmentCount += 1
        }
        return attachmentCount
    }

    func paragraphStyle(containing text: String) -> NSParagraphStyle? {
        let range = (string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            return nil
        }

        return attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }

    func range(of text: String) -> NSRange? {
        let range = (string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            return nil
        }

        return range
    }

    func font(containing text: String) -> UIFont? {
        guard let range = range(of: text) else {
            return nil
        }

        return attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
    }

    func baselineOffset(containing text: String) -> CGFloat? {
        guard let range = range(of: text) else {
            return nil
        }

        return attribute(.baselineOffset, at: range.location, effectiveRange: nil) as? CGFloat
    }

    func blockQuoteBarPositions(containing text: String) -> [CGFloat]? {
        guard let range = range(of: text) else {
            return nil
        }

        return attribute(
            .chatBlockQuoteBarPositions,
            at: range.location,
            effectiveRange: nil
        ) as? [CGFloat]
    }
}
