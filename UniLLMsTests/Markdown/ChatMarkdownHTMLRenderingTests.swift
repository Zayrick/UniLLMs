//
//  ChatMarkdownHTMLRenderingTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownHTMLRenderingTests: ChatMarkdownRenderingTestCase {
    func testMarkdownInlineHTMLRendersGFMTextSemantics() throws {
        let attributedText = renderMarkdownText(
            "A <strong>bold</strong> <em>italic</em> <code>code</code> H<sub>2</sub>O x<sup>2</sup><br/>next"
        )

        XCTAssertEqual(attributedText.string, "A bold italic code H2O x2\nnext")
        XCTAssertTrue(try XCTUnwrap(attributedText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(try XCTUnwrap(attributedText.font(containing: "italic")).fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: try XCTUnwrap(attributedText.range(of: "code")).location,
                effectiveRange: nil
            ) as? UIColor
        )
        XCTAssertLessThan(
            try XCTUnwrap(attributedText.baselineOffset(containing: "2O")),
            0.0
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(attributedText.baselineOffset(containing: "2\n")),
            0.0
        )
    }

    func testMarkdownHTMLBlockRendersAllowedTagsAndFiltersDisallowedGFMRawHTML() throws {
        let attributedText = renderMarkdownText(
            """
            <dl>
              <dt>Definition title</dt>
              <dd>Definition body with <strong>strong HTML</strong>, <code>inline HTML code</code>, and &copy;.</dd>
            </dl>

            <script>alert(1)</script>
            """
        )

        XCTAssertTrue(attributedText.string.contains("Definition title"))
        XCTAssertTrue(attributedText.string.contains("Definition body with strong HTML, inline HTML code, and ©."))
        XCTAssertFalse(attributedText.string.contains("<dl>"))
        XCTAssertFalse(attributedText.string.contains("<strong>"))
        XCTAssertTrue(attributedText.string.contains("<script>"))
        XCTAssertTrue(attributedText.string.contains("</script>"))
        XCTAssertTrue(try XCTUnwrap(attributedText.font(containing: "strong HTML")).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: try XCTUnwrap(attributedText.range(of: "inline HTML code")).location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownHTMLBlockDecodesCommonNamedEntitiesWithoutHTMLImporter() {
        let attributedText = renderMarkdownText("Symbols: &copy; &trade; &mdash; &notareal;")

        XCTAssertEqual(attributedText.string, "Symbols: © ™ — &notareal;")
    }

    func testMarkdownHTMLTagFilterKeepsAllGFMDisallowedRawTagsLiteral() {
        let attributedText = renderMarkdownText(
            """
            <title>T</title>
            <textarea>T</textarea>
            <style>T</style>
            <xmp>T</xmp>
            <iframe>T</iframe>
            <noembed>T</noembed>
            <noframes>T</noframes>
            <script>T</script>
            <plaintext>T</plaintext>
            """
        )

        for tagName in ChatMarkdownHTMLSupport.disallowedRawHTMLTagNames {
            XCTAssertTrue(attributedText.string.contains("<\(tagName)>"))
            XCTAssertTrue(attributedText.string.contains("</\(tagName)>"))
        }
    }

    func testMarkdownHTMLTagFilterDoesNotRenderNestedTagsInsideDisallowedRawHTML() throws {
        let attributedText = renderMarkdownText(
            #"<script><strong>not bold</strong><img src="https://example.com/x.png"><details><summary>Hidden</summary></details></script>"#
        )

        XCTAssertTrue(attributedText.string.contains(#"<strong>not bold</strong>"#))
        XCTAssertTrue(attributedText.string.contains(#"<img src="https://example.com/x.png">"#))
        XCTAssertTrue(attributedText.string.contains("<details><summary>Hidden</summary></details>"))
        XCTAssertFalse(
            try XCTUnwrap(attributedText.font(containing: "not bold"))
                .fontDescriptor
                .symbolicTraits
                .contains(.traitBold)
        )
    }

    func testMarkdownHTMLCommentsAndCustomAnchorsDoNotRenderVisibleText() {
        let attributedText = renderMarkdownText(
            """
            Before
            <!-- hidden comment -->
            <a name="custom-anchor"></a>
            After
            """
        )

        XCTAssertTrue(attributedText.string.contains("Before"))
        XCTAssertTrue(attributedText.string.contains("After"))
        XCTAssertFalse(attributedText.string.contains("hidden comment"))
        XCTAssertFalse(attributedText.string.contains("custom-anchor"))
    }

    func testMarkdownStandaloneHTMLPictureRendersAsImageBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Intro

            <picture>
              <source media="(prefers-color-scheme: dark)" srcset="https://example.com/dark.png">
              <img alt="Diagram" src="https://example.com/default.png">
            </picture>

            Outro
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text, image, and text blocks")
            return
        }
        guard case let .image(imageBlock) = blocks[1] else {
            XCTFail("Expected HTML picture to render as an image block")
            return
        }

        XCTAssertEqual(imageBlock.source, "https://example.com/default.png")
        XCTAssertEqual(imageBlock.altText, "Diagram")
    }

    func testMarkdownWrappedStandaloneHTMLImageRendersAsImageBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: #"<p><img alt="Diagram" src="https://example.com/default.png"></p>"#
        )

        guard blocks.count == 1,
              case let .image(imageBlock) = blocks[0] else {
            XCTFail("Expected wrapped HTML image to render as an image block")
            return
        }

        XCTAssertEqual(imageBlock.source, "https://example.com/default.png")
        XCTAssertEqual(imageBlock.altText, "Diagram")
    }

    func testMarkdownHTMLTableRendersAsNativeTableBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Before

            <table>
              <thead>
                <tr><th>Name</th><th align="right">Score</th></tr>
              </thead>
              <tbody>
                <tr><td><strong>Ada</strong></td><td align="right">99</td></tr>
              </tbody>
            </table>

            After
            """
        )

        guard blocks.count == 3,
              case let .table(tableData) = blocks[1] else {
            XCTFail("Expected HTML table to render as a native table block")
            return
        }

        XCTAssertEqual(tableData.columnCount, 2)
        XCTAssertEqual(tableData.rows.count, 2)
        XCTAssertEqual(tableData.rows[0][0].accessibilityText, "Name")
        XCTAssertEqual(tableData.rows[0][1].accessibilityText, "Score")
        XCTAssertTrue(tableData.rows[0][0].isHeader)
        XCTAssertEqual(tableData.rows[0][1].alignment, .right)
        XCTAssertEqual(tableData.rows[1][0].accessibilityText, "Ada")
        XCTAssertTrue(try XCTUnwrap(tableData.rows[1][0].attributedText.font(containing: "Ada")).fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testMarkdownHTMLDetailsCreatesGitHubStyleDetailsBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            <summary><strong>More</strong> info</summary>

            Inside **bold** body.

            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0] else {
            XCTFail("Expected a single details block")
            return
        }
        guard detailsBlock.children.count == 1,
              case let .text(bodyText) = detailsBlock.children[0] else {
            XCTFail("Expected details body to render Markdown children")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "More info")
        XCTAssertFalse(detailsBlock.isOpen)
        XCTAssertEqual(bodyText.string, "Inside bold body.")
        XCTAssertTrue(try XCTUnwrap(bodyText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testMarkdownHTMLDetailsRendersBodyInOpeningHTMLBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: #"""
            <details>
            <summary>More info</summary>
            Inside **bold** body.

            <p><img alt="Diagram" src="https://example.com/default.png"></p>

            </details>
            """#
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0] else {
            XCTFail("Expected a single details block")
            return
        }
        guard detailsBlock.children.count == 2,
              case let .text(bodyText) = detailsBlock.children[0],
              case let .image(imageBlock) = detailsBlock.children[1] else {
            XCTFail("Expected details body text and image to render as child blocks")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "More info")
        XCTAssertEqual(bodyText.string, "Inside bold body.")
        XCTAssertTrue(try XCTUnwrap(bodyText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(imageBlock.source, "https://example.com/default.png")
        XCTAssertEqual(imageBlock.altText, "Diagram")
    }

    func testMarkdownHTMLDetailsWithoutSummaryUsesDefaultSummaryAndKeepsBody() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            Body without summary.
            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0],
              detailsBlock.children.count == 1,
              case let .text(bodyText) = detailsBlock.children[0] else {
            XCTFail("Expected details body text")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "Details")
        XCTAssertEqual(bodyText.string, "Body without summary.")
    }

    func testMarkdownHTMLDetailsBodyPreservesMarkdownSourceBeforeNestedRendering() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            <summary>Escaped source</summary>
            Use &lt;tag&gt; &amp; **bold** text.
            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0],
              detailsBlock.children.count == 1,
              case let .text(bodyText) = detailsBlock.children[0] else {
            XCTFail("Expected details body text")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "Escaped source")
        XCTAssertEqual(bodyText.string, "Use <tag> & bold text.")
        XCTAssertTrue(try XCTUnwrap(bodyText.font(containing: "bold")).fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testMarkdownHTMLDetailsKeepsNestedDetailsInsideOuterBody() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details>
            <summary>Outer</summary>

            Before

            <details><summary>Inner</summary>Inner body</details>

            After

            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(outerDetails) = blocks[0] else {
            XCTFail("Expected a single outer details block")
            return
        }
        guard outerDetails.children.count == 3,
              case let .text(beforeText) = outerDetails.children[0],
              case let .details(innerDetails) = outerDetails.children[1],
              case let .text(afterText) = outerDetails.children[2] else {
            XCTFail("Expected outer details to contain before text, nested details, and after text")
            return
        }
        guard innerDetails.children.count == 1,
              case let .text(innerText) = innerDetails.children[0] else {
            XCTFail("Expected inner details body text")
            return
        }

        XCTAssertEqual(outerDetails.summary, "Outer")
        XCTAssertEqual(beforeText.string, "Before")
        XCTAssertEqual(innerDetails.summary, "Inner")
        XCTAssertEqual(innerText.string, "Inner body")
        XCTAssertEqual(afterText.string, "After")
    }

    func testMarkdownHTMLOpenDetailsStartsExpanded() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            <details open>
            <summary>Open section</summary>

            Body

            </details>
            """
        )

        guard blocks.count == 1,
              case let .details(detailsBlock) = blocks[0] else {
            XCTFail("Expected a details block")
            return
        }

        XCTAssertEqual(detailsBlock.summary, "Open section")
        XCTAssertTrue(detailsBlock.isOpen)
    }
}
