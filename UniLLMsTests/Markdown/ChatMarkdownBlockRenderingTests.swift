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

    func testMarkdownBlockQuoteNestedCodeBlockRendersAsIndentedCodeBlockCard() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            > Before
            >
            > ```swift
            > let value = 1
            > ```
            >
            > After
            """
        )

        guard blocks.count == 1,
              case let .blockQuote(blockQuoteBlock) = blocks[0] else {
            XCTFail("Expected block quote to render as a container")
            return
        }
        guard blockQuoteBlock.children.count == 3,
              case let .text(beforeText) = blockQuoteBlock.children[0],
              case let .codeBlock(codeBlock) = blockQuoteBlock.children[1],
              case let .text(afterText) = blockQuoteBlock.children[2] else {
            XCTFail("Expected quoted text, code block card, and trailing quoted text")
            return
        }

        XCTAssertEqual(beforeText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Before")
        XCTAssertEqual(codeBlock.displayLanguage, "swift")
        XCTAssertEqual(codeBlock.code, "let value = 1")
        XCTAssertEqual(afterText.string.trimmingCharacters(in: .whitespacesAndNewlines), "After")
    }

    func testMarkdownListNestedCodeBlockRendersAsCodeBlockChild() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            - Item
              ```swift
              let value = 1
              ```
            """
        )

        guard blocks.count == 1,
              case let .list(listBlock) = blocks[0],
              listBlock.items.count == 1,
              listBlock.items[0].children.count == 2,
              case let .text(itemText) = listBlock.items[0].children[0],
              case let .codeBlock(codeBlock) = listBlock.items[0].children[1] else {
            XCTFail("Expected list item to preserve nested code block card")
            return
        }

        XCTAssertEqual(itemText.string, "Item")
        XCTAssertEqual(codeBlock.displayLanguage, "swift")
        XCTAssertEqual(codeBlock.code, "let value = 1")
    }

    func testMarkdownBlockQuoteListNestedCodeBlockRendersAsIndentedCodeBlockCard() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            > - Item
            >   ```swift
            >   let value = 1
            >   ```
            """
        )

        guard blocks.count == 1,
              case let .blockQuote(blockQuoteBlock) = blocks[0],
              blockQuoteBlock.children.count == 1,
              case let .list(listBlock) = blockQuoteBlock.children[0],
              listBlock.items.count == 1,
              listBlock.items[0].children.count == 2,
              case let .text(itemText) = listBlock.items[0].children[0],
              case let .codeBlock(codeBlock) = listBlock.items[0].children[1] else {
            XCTFail("Expected quoted list item to preserve nested code block card")
            return
        }

        XCTAssertEqual(itemText.string, "Item")
        XCTAssertEqual(codeBlock.displayLanguage, "swift")
        XCTAssertEqual(codeBlock.code, "let value = 1")
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
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "- [ ] Todo")

        guard blocks.count == 1,
              case let .list(listBlock) = blocks[0],
              listBlock.items.count == 1,
              case .checkbox(isChecked: false) = listBlock.items[0].marker,
              listBlock.items[0].children.count == 1,
              case let .text(todoText) = listBlock.items[0].children[0] else {
            XCTFail("Expected task list to render as a list block with an unchecked marker")
            return
        }

        XCTAssertEqual(todoText.string, "Todo")
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
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "- Parent\n  - Child\n    - Grandchild")

        guard blocks.count == 1,
              case let .list(parentList) = blocks[0],
              parentList.items.count == 1,
              parentList.items[0].children.count == 2,
              case let .text(parentText) = parentList.items[0].children[0],
              case let .list(childList) = parentList.items[0].children[1],
              childList.items.count == 1,
              childList.items[0].children.count == 2,
              case let .text(childText) = childList.items[0].children[0],
              case let .list(grandchildList) = childList.items[0].children[1],
              grandchildList.items.count == 1,
              grandchildList.items[0].children.count == 1,
              case let .text(grandchildText) = grandchildList.items[0].children[0] else {
            XCTFail("Expected nested Markdown lists to render as nested list blocks")
            return
        }

        XCTAssertEqual(parentText.string, "Parent")
        XCTAssertEqual(childText.string, "Child")
        XCTAssertEqual(grandchildText.string, "Grandchild")
    }

    func testMarkdownBlockQuotePreservesNestedListIndents() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "> - Parent\n>   - Child\n>     - Grandchild")

        guard blocks.count == 1,
              case let .blockQuote(blockQuoteBlock) = blocks[0],
              blockQuoteBlock.children.count == 1,
              case let .list(parentList) = blockQuoteBlock.children[0],
              parentList.items.count == 1,
              parentList.items[0].children.count == 2,
              case let .list(childList) = parentList.items[0].children[1],
              childList.items.count == 1,
              childList.items[0].children.count == 2,
              case let .list(grandchildList) = childList.items[0].children[1],
              grandchildList.items.count == 1 else {
            XCTFail("Expected quoted nested list to render as a block quote containing nested list blocks")
            return
        }

        XCTAssertFalse(parentList.isOrdered)
        XCTAssertFalse(childList.isOrdered)
        XCTAssertFalse(grandchildList.isOrdered)
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
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "- Item\n  > Quote")

        guard blocks.count == 1,
              case let .list(listBlock) = blocks[0],
              listBlock.items.count == 1,
              listBlock.items[0].children.count == 2,
              case let .text(itemText) = listBlock.items[0].children[0],
              case let .text(quoteText) = listBlock.items[0].children[1] else {
            XCTFail("Expected list item to contain text and a nested quote text block")
            return
        }

        XCTAssertEqual(itemText.string, "Item")
        XCTAssertEqual(quoteText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Quote")
    }

    func testMarkdownListContinuationOffsetsNestedBlockQuoteBarPosition() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "- Item\n  > Quote")

        guard blocks.count == 1,
              case let .list(listBlock) = blocks[0],
              listBlock.items.count == 1,
              listBlock.items[0].children.count == 2,
              case let .text(quoteText) = listBlock.items[0].children[1] else {
            XCTFail("Expected list item to preserve nested quote text")
            return
        }
        let positions = try XCTUnwrap(quoteText.blockQuoteBarPositions(containing: "Quote"))

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0], ChatMarkdownBlockQuoteStyle.barLeading, accuracy: 0.001)
    }

    func testMarkdownBlockQuoteKeepsOuterBarBeforeNestedListMarker() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "> - Item")

        guard blocks.count == 1,
              case let .blockQuote(blockQuoteBlock) = blocks[0],
              blockQuoteBlock.children.count == 1,
              case let .list(listBlock) = blockQuoteBlock.children[0],
              listBlock.items.count == 1,
              listBlock.items[0].children.count == 1,
              case let .text(itemText) = listBlock.items[0].children[0] else {
            XCTFail("Expected block quote to contain a nested list block")
            return
        }

        XCTAssertEqual(itemText.string, "Item")
    }

    func testMarkdownBlockQuoteNestedTablePreservesCellInlineStyles() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            > | Value | Code |
            > | :-- | :-- |
            > | ***Cell*** | `id` |
            """
        )

        guard blocks.count == 1,
              case let .blockQuote(blockQuoteBlock) = blocks[0],
              blockQuoteBlock.children.count == 1,
              case let .table(tableData) = blockQuoteBlock.children[0] else {
            XCTFail("Expected quoted table to render as an indented table block")
            return
        }

        let attributedText = tableData.rows[1][0].attributedText
        let cellFont = try XCTUnwrap(attributedText.font(containing: "Cell"))
        let cellTraits = cellFont.fontDescriptor.symbolicTraits
        let codeText = tableData.rows[1][1].attributedText
        let codeRange = try XCTUnwrap(codeText.range(of: "id"))

        XCTAssertTrue(cellTraits.contains(.traitBold))
        XCTAssertTrue(cellTraits.contains(.traitItalic))
        XCTAssertNotNil(
            codeText.attribute(
                .chatInlineCodeBackgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
    }

    func testMarkdownOrderedListUsesStableContentIndentAcrossDigitWidths() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "9. Nine\n10. Ten")

        guard blocks.count == 1,
              case let .list(listBlock) = blocks[0],
              listBlock.isOrdered,
              listBlock.items.count == 2,
              case let .text(firstMarker) = listBlock.items[0].marker,
              case let .text(secondMarker) = listBlock.items[1].marker else {
            XCTFail("Expected ordered list to render as one ordered list block")
            return
        }

        XCTAssertEqual(firstMarker, "9.")
        XCTAssertEqual(secondMarker, "10.")
    }

    func testMarkdownTaskListRendersCheckboxMarkers() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(markdown: "- [x] Done\n- [ ] Todo")

        guard blocks.count == 1,
              case let .list(listBlock) = blocks[0],
              listBlock.items.count == 2,
              case .checkbox(isChecked: true) = listBlock.items[0].marker,
              case .checkbox(isChecked: false) = listBlock.items[1].marker,
              case let .text(doneText) = listBlock.items[0].children[0],
              case let .text(todoText) = listBlock.items[1].children[0] else {
            XCTFail("Expected task list checkbox markers and text children")
            return
        }

        XCTAssertEqual(doneText.string, "Done")
        XCTAssertEqual(todoText.string, "Todo")
    }
}
