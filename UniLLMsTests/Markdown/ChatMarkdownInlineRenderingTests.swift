//
//  ChatMarkdownInlineRenderingTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownInlineRenderingTests: ChatMarkdownRenderingTestCase {
    @MainActor
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

    @MainActor
    func testMarkdownInlineCodeAddsOuterMarginWhenAdjacentToText() {
        let attributedText = renderMarkdownText("A`code`B")

        XCTAssertEqual(attributedText.string, "A code B")
    }

    @MainActor
    func testMarkdownNestedStrongEmphasisCombinesFontTraits() throws {
        let attributedText = renderMarkdownText("***Bold italic***")
        let font = try XCTUnwrap(attributedText.font(containing: "Bold italic"))
        let traits = font.fontDescriptor.symbolicTraits

        XCTAssertTrue(traits.contains(.traitBold))
        XCTAssertTrue(traits.contains(.traitItalic))
    }

    @MainActor
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
}
