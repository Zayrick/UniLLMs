//
//  ChatMarkdownRenderingTestCase.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

fileprivate struct TestLinkAttribute: AttributedStringKey {
    typealias Value = URL
    static let name = "NSLink"
}

fileprivate struct TestBaselineOffsetAttribute: AttributedStringKey {
    typealias Value = CGFloat
    static let name = "NSBaselineOffset"
}

fileprivate struct TestFontSymbolicTraitsAttribute: AttributedStringKey {
    typealias Value = UInt32
    static let name = "UniLLMs.ChatMarkdown.fontSymbolicTraits"
}

fileprivate struct TestInlineCodeCornerRadiusAttribute: AttributedStringKey {
    typealias Value = CGFloat
    static let name = "UniLLMs.ChatMarkdown.inlineCodeCornerRadius"
}

fileprivate struct TestBlockQuoteBarPositionsAttribute: AttributedStringKey {
    typealias Value = [CGFloat]
    static let name = "UniLLMs.ChatMarkdown.blockQuoteBarPositions"
}

fileprivate struct ChatMarkdownTestAttributeScope: AttributeScope {
    let link: TestLinkAttribute
    let baselineOffset: TestBaselineOffsetAttribute
    let fontSymbolicTraits: TestFontSymbolicTraitsAttribute
    let inlineCodeCornerRadius: TestInlineCodeCornerRadiusAttribute
    let blockQuoteBarPositions: TestBlockQuoteBarPositionsAttribute
}

extension AttributeScopes {
    fileprivate var chatMarkdownTests: ChatMarkdownTestAttributeScope.Type {
        ChatMarkdownTestAttributeScope.self
    }
}

struct ChatMarkdownParagraphMetrics: Sendable {
    let firstLineHeadIndent: CGFloat
    let headIndent: CGFloat
}

class ChatMarkdownRenderingTestCase: XCTestCase {
    @MainActor
    var markdownRendererTraits: UITraitCollection {
        UITraitCollection { traits in
            traits.displayScale = 2.0
            traits.preferredContentSizeCategory = .large
        }
    }

    @MainActor
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

@MainActor
extension NSAttributedString {
    var containsTextAttachment: Bool {
        textAttachmentCount > 0
    }

    var textAttachmentCount: Int {
        string.filter { $0 == "\u{fffc}" }.count
    }

    func hasAttachment(at location: Int) -> Bool {
        let nsString = string as NSString
        guard location >= 0, location < nsString.length else {
            return false
        }
        return nsString.character(at: location) == 0xfffc
    }

    func range(of text: String) -> NSRange? {
        let range = (string as NSString).range(of: text)
        guard range.location != NSNotFound else {
            return nil
        }

        return range
    }

    func paragraphMetrics(containing text: String) -> ChatMarkdownParagraphMetrics? {
        guard let range = range(of: text) else {
            return nil
        }

        guard let paragraphStyle = attribute(
            .paragraphStyle,
            at: range.location,
            effectiveRange: nil
        ) as? NSParagraphStyle else {
            return nil
        }

        return ChatMarkdownParagraphMetrics(
            firstLineHeadIndent: paragraphStyle.firstLineHeadIndent,
            headIndent: paragraphStyle.headIndent
        )
    }

    func fontSymbolicTraits(containing text: String) -> UIFontDescriptor.SymbolicTraits? {
        guard let range = range(of: text) else {
            return nil
        }

        return fontSymbolicTraits(at: range.location)
    }

    func link(at location: Int) -> URL? {
        testAttribute(TestLinkAttribute.self, at: location)
    }

    func fontSymbolicTraits(at location: Int) -> UIFontDescriptor.SymbolicTraits? {
        guard let rawValue = testAttribute(TestFontSymbolicTraitsAttribute.self, at: location) else {
            return nil
        }
        return UIFontDescriptor.SymbolicTraits(rawValue: rawValue)
    }

    func inlineCodeCornerRadius(at location: Int) -> CGFloat? {
        testAttribute(TestInlineCodeCornerRadiusAttribute.self, at: location)
    }

    func hasStandardBackgroundColor(at location: Int) -> Bool {
        attribute(.backgroundColor, at: location, effectiveRange: nil) != nil
    }

    func baselineOffset(containing text: String) -> CGFloat? {
        guard let range = range(of: text) else {
            return nil
        }

        return testAttribute(TestBaselineOffsetAttribute.self, at: range.location)
    }

    func blockQuoteBarPositions(containing text: String) -> [CGFloat]? {
        guard let range = range(of: text) else {
            return nil
        }

        return testAttribute(TestBlockQuoteBarPositionsAttribute.self, at: range.location)
    }

    private func testAttribute<Key: AttributedStringKey>(
        _ key: Key.Type,
        at location: Int
    ) -> Key.Value? where Key.Value: Sendable {
        for run in testRuns() {
            guard location >= run.location,
                  location < run.location + run.length else {
                continue
            }

            return run.value[key]
        }
        return nil
    }

    private func testRuns() -> [(location: Int, length: Int, value: AttributedString.Runs.Run)] {
        guard let attributedString = try? AttributedString(
            self,
            including: \.chatMarkdownTests
        ) else {
            return []
        }

        var location = 0
        var runs: [(location: Int, length: Int, value: AttributedString.Runs.Run)] = []
        for run in attributedString.runs {
            let length = String(attributedString.characters[run.range]).utf16.count
            runs.append((location, length, run))
            location += length
        }
        return runs
    }
}
