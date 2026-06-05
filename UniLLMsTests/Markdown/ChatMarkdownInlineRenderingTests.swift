//
//  ChatMarkdownInlineRenderingTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownInlineRenderingTests: ChatMarkdownRenderingTestCase {
    func testMarkdownInlineCodeUsesRoundedPillAttributesWithoutTextPadding() throws {
        let attributedText = renderMarkdownText("Use `let value = 1` now")
        let codeRange = try XCTUnwrap(attributedText.range(of: "let value = 1"))

        XCTAssertEqual(attributedText.string, "Use let value = 1 now")
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
        let cornerRadius = try XCTUnwrap(
            attributedText.attribute(
                .chatInlineCodeCornerRadius,
                at: codeRange.location,
                effectiveRange: nil
            ) as? CGFloat
        )
        XCTAssertEqual(cornerRadius, ChatMarkdownInlineCodeStyle.cornerRadius)
        XCTAssertNil(
            attributedText.attribute(
                .backgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            )
        )
    }

    func testMarkdownInlineCodeAddsVisualSpacingWhenAdjacentToTextWithoutChangingString() throws {
        let attributedText = renderMarkdownText("A`code`B")
        let codeRange = try XCTUnwrap(attributedText.range(of: "code"))

        XCTAssertEqual(attributedText.string, "AcodeB")
        XCTAssertEqual(
            attributedText.kern(at: 0),
            ChatMarkdownInlineCodeStyle.boundarySpacing
        )
        XCTAssertEqual(
            attributedText.kern(at: NSMaxRange(codeRange) - 1),
            ChatMarkdownInlineCodeStyle.boundarySpacing
        )
        XCTAssertEqual(
            attributedText.attribute(
                .chatInlineCodeBoundarySpacing,
                at: 0,
                effectiveRange: nil
            ) as? CGFloat,
            ChatMarkdownInlineCodeStyle.boundarySpacing
        )
    }

    func testMarkdownInlineCodeDoesNotInsertSpacesBeforePunctuation() throws {
        let attributedText = renderMarkdownText("Use `x`, then `y`.")
        let xRange = try XCTUnwrap(attributedText.range(of: "x"))
        let yRange = try XCTUnwrap(attributedText.range(of: "y"))

        XCTAssertEqual(attributedText.string, "Use x, then y.")
        XCTAssertEqual(
            attributedText.kern(at: NSMaxRange(xRange) - 1),
            ChatMarkdownInlineCodeStyle.boundarySpacing
        )
        XCTAssertEqual(
            attributedText.kern(at: NSMaxRange(yRange) - 1),
            ChatMarkdownInlineCodeStyle.boundarySpacing
        )
    }

    func testMarkdownTextViewLeavesHorizontalDrawingRoomForLineEdgeInlineCode() {
        let attributedText = renderMarkdownText("`code` at line start")
        let textView = ChatMarkdownTextView(attributedText: attributedText)

        XCTAssertEqual(
            textView.textContainer.lineFragmentPadding,
            ChatMarkdownInlineCodeStyle.horizontalPadding
        )
    }

    func testMarkdownEmphasisAppliesItalicObliqueness() throws {
        let attributedText = renderMarkdownText("*Italic text*")

        try assertItalicPresentation(attributedText, containing: "Italic text")
    }

    func testMarkdownChineseEmphasisAppliesItalicObliqueness() throws {
        let attributedText = renderMarkdownText("*中文斜体*")

        try assertItalicPresentation(attributedText, containing: "中文斜体")
    }

    func testMarkdownNestedStrongEmphasisCombinesBoldAndItalicPresentation() throws {
        let attributedText = renderMarkdownText("***Bold italic***")
        let font = try XCTUnwrap(attributedText.font(containing: "Bold italic"))
        let traits = font.fontDescriptor.symbolicTraits

        XCTAssertTrue(traits.contains(.traitBold))
        try assertItalicPresentation(attributedText, containing: "Bold italic")
    }

    func testMarkdownStrongContainingEmphasisPreservesBoldAndItalicPresentation() throws {
        let attributedText = renderMarkdownText("**Bold and _italic_**")
        let font = try XCTUnwrap(attributedText.font(containing: "italic"))
        let traits = font.fontDescriptor.symbolicTraits

        XCTAssertTrue(traits.contains(.traitBold))
        try assertItalicPresentation(attributedText, containing: "italic")
    }

    func testMarkdownNestedInlineCodePreservesOuterModes() throws {
        let attributedText = renderMarkdownText("[**`id`**](https://example.com)")
        let codeRange = try XCTUnwrap(attributedText.range(of: "id"))
        let font = try XCTUnwrap(
            attributedText.attribute(.font, at: codeRange.location, effectiveRange: nil) as? UIFont
        )

        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(
            attributedText.attribute(.link, at: codeRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://example.com")
        )
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownEmphasisContainingInlineCodePreservesItalicPresentation() throws {
        let attributedText = renderMarkdownText("*`id`*")
        let codeRange = try XCTUnwrap(attributedText.range(of: "id"))

        try assertItalicPresentation(attributedText, containing: "id")
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownFootnoteReferenceRendersAsSuperscriptLinkAndHidesDefinition() throws {
        let attributedText = renderMarkdownText(
            """
            Fact[^note].

            [^note]: Details **here**
            """
        )
        let footnoteRange = try XCTUnwrap(attributedText.range(of: "1"))
        let link = try XCTUnwrap(
            attributedText.attribute(.link, at: footnoteRange.location, effectiveRange: nil) as? URL
        )
        let footnoteContent = try XCTUnwrap(
            attributedText.attribute(
                .chatFootnoteContent,
                at: footnoteRange.location,
                effectiveRange: nil
            ) as? String
        )
        let footnoteFont = try XCTUnwrap(
            attributedText.attribute(.font, at: footnoteRange.location, effectiveRange: nil) as? UIFont
        )
        let bodyFont = try XCTUnwrap(attributedText.font(containing: "Fact"))
        let baselineOffset = try XCTUnwrap(attributedText.baselineOffset(containing: "1"))

        XCTAssertEqual(attributedText.string, "Fact1.")
        XCTAssertEqual(link.scheme, ChatMarkdownFootnoteLink.scheme)
        XCTAssertEqual(footnoteContent, "Details **here**")
        XCTAssertLessThan(footnoteFont.pointSize, bodyFont.pointSize)
        XCTAssertGreaterThan(baselineOffset, 0.0)
        XCTAssertFalse(attributedText.string.contains("[^note]:"))
    }

    func testMarkdownFootnoteDefinitionSupportsIndentedContinuation() throws {
        let attributedText = renderMarkdownText(
            """
            Fact[^a].

            [^a]: First line
                Second line
            """
        )
        let footnoteRange = try XCTUnwrap(attributedText.range(of: "1"))
        let footnoteContent = try XCTUnwrap(
            attributedText.attribute(
                .chatFootnoteContent,
                at: footnoteRange.location,
                effectiveRange: nil
            ) as? String
        )

        XCTAssertEqual(attributedText.string, "Fact1.")
        XCTAssertEqual(footnoteContent, "First line\nSecond line")
    }

    func testMarkdownRepeatedFootnoteReferenceUsesSameNumber() {
        let attributedText = renderMarkdownText(
            """
            A[^same] B[^same].

            [^same]: Shared note
            """
        )

        XCTAssertEqual(attributedText.string, "A1 B1.")
    }

    func testMarkdownUndefinedFootnoteReferenceStaysLiteral() {
        let attributedText = renderMarkdownText("Fact[^missing].")

        XCTAssertEqual(attributedText.string, "Fact[^missing].")
        XCTAssertNil(attributedText.range(of: "missing").flatMap { range in
            attributedText.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        })
    }

    private func assertItalicPresentation(
        _ attributedText: NSAttributedString,
        containing text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let range = try XCTUnwrap(attributedText.range(of: text), file: file, line: line)
        let obliqueness = try XCTUnwrap(
            attributedText.attribute(.obliqueness, at: range.location, effectiveRange: nil) as? NSNumber,
            file: file,
            line: line
        )

        XCTAssertGreaterThan(obliqueness.doubleValue, 0.0, file: file, line: line)
    }
}
