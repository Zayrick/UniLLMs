//
//  ChatMarkdownBlockRenderingTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownBlockRenderingTests: ChatMarkdownRenderingTestCase {
    func testMarkdownThematicBreakRendersAsVisualDivider() throws {
        let attributedText = renderMarkdownText("Above\n\n---\n\nBelow")

        XCTAssertFalse(attributedText.string.contains("---"))
        XCTAssertTrue(attributedText.string.contains("Above"))
        XCTAssertTrue(attributedText.string.contains("Below"))
        XCTAssertTrue(attributedText.containsTextAttachment)
    }

    func testMarkdownTableRendersAsDedicatedBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            | Feature | Count |
            | :-- | --: |
            | **Tables** | 2 |
            """
        )

        let firstBlock = try XCTUnwrap(blocks.first)
        guard case let .table(tableData) = firstBlock else {
            XCTFail("Expected first rendered block to be a Markdown table")
            return
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(tableData.columnCount, 2)
        XCTAssertEqual(tableData.rows.count, 2)
        XCTAssertEqual(tableData.rows[0][0].accessibilityText, "Feature")
        XCTAssertEqual(tableData.rows[1][0].accessibilityText, "Tables")
    }

    func testMarkdownCodeBlockRendersAsDedicatedBlockWithLanguageFallback() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Intro

            ```swift
            let value = 1
            ```

            ```
            plain
            ```
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text and two code blocks")
            return
        }
        guard case let .text(introText) = blocks[0] else {
            XCTFail("Expected leading text block")
            return
        }
        guard case let .codeBlock(swiftCodeBlock) = blocks[1] else {
            XCTFail("Expected Swift code block")
            return
        }
        guard case let .codeBlock(fallbackCodeBlock) = blocks[2] else {
            XCTFail("Expected fallback code block")
            return
        }

        XCTAssertEqual(introText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Intro")
        XCTAssertEqual(swiftCodeBlock.displayLanguage, "swift")
        XCTAssertEqual(swiftCodeBlock.code, "let value = 1")
        XCTAssertEqual(fallbackCodeBlock.displayLanguage, "Code")
        XCTAssertEqual(fallbackCodeBlock.code, "plain")
    }

    func testMarkdownStandaloneImageRendersAsDedicatedBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Intro

            ![Architecture](https://example.com/diagram.png)

            Outro
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text, image, and text blocks")
            return
        }
        guard case let .text(introText) = blocks[0] else {
            XCTFail("Expected leading text block")
            return
        }
        guard case let .image(imageBlock) = blocks[1] else {
            XCTFail("Expected standalone image block")
            return
        }
        guard case let .text(outroText) = blocks[2] else {
            XCTFail("Expected trailing text block")
            return
        }

        XCTAssertEqual(introText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Intro")
        XCTAssertEqual(imageBlock.source, "https://example.com/diagram.png")
        XCTAssertEqual(imageBlock.altText, "Architecture")
        XCTAssertEqual(outroText.string, "Outro")
    }

    func testMarkdownTaskListUsesSymbolAttachmentWithReadableAccessibilityText() throws {
        let rendered = renderMarkdownText("- [ ] Todo")

        let attachment = rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(attachment)
        XCTAssertTrue(rendered.chatAccessibilityString.contains("Unchecked"))
        XCTAssertFalse(rendered.chatAccessibilityString.contains("\u{fffc}"))
    }

    func testMarkdownBareURLUsesRendererLinkAttribute() throws {
        let rendered = renderMarkdownText("Visit https://example.com/docs now")
        let linkRange = (rendered.string as NSString).range(of: "https://example.com/docs")

        let url = rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL

        XCTAssertEqual(url?.absoluteString, "https://example.com/docs")
    }

    func testMarkdownRendererKeepsSingleColumnPipeTableAsTable() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            | A |
            | --- |
            | x |
            """
        )

        let firstBlock = try XCTUnwrap(blocks.first)
        guard case let .table(tableData) = firstBlock else {
            XCTFail("Expected first rendered block to be a Markdown table")
            return
        }

        XCTAssertEqual(tableData.columnCount, 1)
        XCTAssertEqual(tableData.rows.count, 2)
    }

    func testMarkdownTableInlineCodeUsesRoundedPillAttributesAndCleanAccessibilityText() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            | Code |
            | :-- |
            | `id` |
            """
        )

        let firstBlock = try XCTUnwrap(blocks.first)
        guard case let .table(tableData) = firstBlock else {
            XCTFail("Expected first rendered block to be a Markdown table")
            return
        }

        let codeCell = tableData.rows[1][0]
        let codeRange = try XCTUnwrap(codeCell.attributedText.range(of: "id"))

        XCTAssertEqual(codeCell.accessibilityText, "id")
        XCTAssertNotNil(
            codeCell.attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownTableNestedStrongEmphasisCombinesFontTraits() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            | Value |
            | :-- |
            | ***Cell*** |
            """
        )

        let firstBlock = try XCTUnwrap(blocks.first)
        guard case let .table(tableData) = firstBlock else {
            XCTFail("Expected first rendered block to be a Markdown table")
            return
        }

        let font = try XCTUnwrap(tableData.rows[1][0].attributedText.font(containing: "Cell"))
        let traits = font.fontDescriptor.symbolicTraits

        XCTAssertTrue(traits.contains(.traitBold))
        XCTAssertTrue(traits.contains(.traitItalic))
    }

    func testMarkdownBlockQuoteNestedInlineStylesCompose() throws {
        let attributedText = renderMarkdownText("> ***Quoted*** `id`")
        let quoteFont = try XCTUnwrap(attributedText.font(containing: "Quoted"))
        let quoteTraits = quoteFont.fontDescriptor.symbolicTraits
        let codeRange = try XCTUnwrap(attributedText.range(of: "id"))
        let paragraphStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Quoted"))

        XCTAssertTrue(quoteTraits.contains(.traitBold))
        XCTAssertTrue(quoteTraits.contains(.traitItalic))
        XCTAssertGreaterThan(paragraphStyle.headIndent, 0.0)
        XCTAssertNotNil(
            attributedText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownNestedListRendersIncreasingIndents() throws {
        let attributedText = renderMarkdownText("- Parent\n  - Child\n    - Grandchild")

        let parentStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Parent"))
        let childStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Child"))
        let grandchildStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Grandchild"))

        XCTAssertGreaterThan(childStyle.firstLineHeadIndent, parentStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(grandchildStyle.firstLineHeadIndent, childStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(childStyle.headIndent, parentStyle.headIndent)
        XCTAssertGreaterThan(grandchildStyle.headIndent, childStyle.headIndent)
    }

    func testMarkdownBlockQuotePreservesNestedListIndents() throws {
        let attributedText = renderMarkdownText("> - Parent\n>   - Child\n>     - Grandchild")

        let parentStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Parent"))
        let childStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Child"))
        let grandchildStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Grandchild"))

        XCTAssertGreaterThan(childStyle.firstLineHeadIndent, parentStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(grandchildStyle.firstLineHeadIndent, childStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(childStyle.headIndent, parentStyle.headIndent)
        XCTAssertGreaterThan(grandchildStyle.headIndent, childStyle.headIndent)
    }

    func testMarkdownNestedBlockQuoteRendersIncreasingIndents() throws {
        let attributedText = renderMarkdownText("> Outer\n>\n> > Inner")

        let outerStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Outer"))
        let innerStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Inner"))

        XCTAssertGreaterThan(innerStyle.firstLineHeadIndent, outerStyle.firstLineHeadIndent)
        XCTAssertGreaterThan(innerStyle.headIndent, outerStyle.headIndent)
    }

    func testMarkdownBlockQuoteStoresBarPositionAtLeadingMargin() throws {
        let attributedText = renderMarkdownText("> Quote")
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Quote"))

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0], ChatMarkdownBlockQuoteStyle.barLeading, accuracy: 0.001)
    }

    func testMarkdownNestedBlockQuoteStoresBarPositionForEachLevel() throws {
        let attributedText = renderMarkdownText("> Outer\n>\n> > Inner")
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Inner"))

        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0], ChatMarkdownBlockQuoteStyle.barLeading, accuracy: 0.001)
        XCTAssertEqual(
            positions[1],
            ChatMarkdownBlockQuoteStyle.barLeading + ChatMarkdownBlockQuoteStyle.indentPerLevel,
            accuracy: 0.001
        )
    }

    func testMarkdownListContinuationPreservesNestedBlockQuoteIndent() throws {
        let attributedText = renderMarkdownText("- Item\n  > Quote")

        let itemStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Item"))
        let quoteStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Quote"))

        XCTAssertGreaterThan(quoteStyle.firstLineHeadIndent, itemStyle.headIndent)
        XCTAssertGreaterThan(quoteStyle.headIndent, itemStyle.headIndent)
    }

    func testMarkdownListContinuationOffsetsNestedBlockQuoteBarPosition() throws {
        let attributedText = renderMarkdownText("- Item\n  > Quote")

        let itemStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Item"))
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Quote"))

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(
            positions[0],
            itemStyle.headIndent + ChatMarkdownBlockQuoteStyle.barLeading,
            accuracy: 0.001
        )
    }

    func testMarkdownBlockQuoteKeepsOuterBarBeforeNestedListMarker() throws {
        let attributedText = renderMarkdownText("> - Item")

        let itemStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Item"))
        let positions = try XCTUnwrap(attributedText.blockQuoteBarPositions(containing: "Item"))

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0], ChatMarkdownBlockQuoteStyle.barLeading, accuracy: 0.001)
        XCTAssertGreaterThan(itemStyle.firstLineHeadIndent, positions[0])
    }

    func testMarkdownOrderedListUsesStableContentIndentAcrossDigitWidths() throws {
        let attributedText = renderMarkdownText("9. Nine\n10. Ten")

        let nineStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Nine"))
        let tenStyle = try XCTUnwrap(attributedText.paragraphStyle(containing: "Ten"))

        XCTAssertEqual(nineStyle.headIndent, tenStyle.headIndent)
    }

    func testMarkdownTaskListRendersCheckboxMarkers() throws {
        let attributedText = renderMarkdownText("- [x] Done\n- [ ] Todo")

        XCTAssertEqual(attributedText.textAttachmentCount, 2)
        XCTAssertTrue(attributedText.string.contains("Done"))
        XCTAssertTrue(attributedText.string.contains("Todo"))
        XCTAssertFalse(attributedText.string.contains("[x]"))
        XCTAssertFalse(attributedText.string.contains("[ ]"))
    }
}
