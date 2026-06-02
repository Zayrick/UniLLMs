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
            attributedText.inlineCodeCornerRadius(at: codeRange.location)
        )
        let cornerRadius = try XCTUnwrap(
            attributedText.inlineCodeCornerRadius(at: codeRange.location)
        )
        XCTAssertEqual(cornerRadius, ChatMarkdownInlineCodeStyle.cornerRadius)
        XCTAssertFalse(attributedText.hasStandardBackgroundColor(at: codeRange.location))
    }

    @MainActor
    func testMarkdownInlineCodeAddsOuterMarginWhenAdjacentToText() {
        let attributedText = renderMarkdownText("A`code`B")

        XCTAssertEqual(attributedText.string, "A code B")
    }

    @MainActor
    func testMarkdownNestedStrongEmphasisCombinesFontTraits() throws {
        let attributedText = renderMarkdownText("***Bold italic***")
        let traits = try XCTUnwrap(attributedText.fontSymbolicTraits(containing: "Bold italic"))

        XCTAssertTrue(traits.contains(.traitBold))
        XCTAssertTrue(traits.contains(.traitItalic))
    }

    @MainActor
    func testMarkdownNestedInlineCodePreservesOuterModes() throws {
        let attributedText = renderMarkdownText("[**`id`**](https://example.com)")
        let codeRange = try XCTUnwrap(attributedText.range(of: "id"))
        let traits = try XCTUnwrap(
            attributedText.fontSymbolicTraits(at: codeRange.location)
        )

        XCTAssertTrue(traits.contains(.traitBold))
        XCTAssertEqual(
            attributedText.link(at: codeRange.location),
            URL(string: "https://example.com")
        )
        XCTAssertNotNil(
            attributedText.inlineCodeCornerRadius(at: codeRange.location)
        )
    }
}
