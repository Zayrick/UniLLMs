//
//  ChatMarkdownMathRenderingTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownMathRenderingTests: ChatMarkdownRenderingTestCase {
    func testMarkdownInlineLatexRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Euler has $e^{i\\pi}+1=0$ inline.")

        XCTAssertTrue(attributedText.string.contains("Euler has "))
        XCTAssertTrue(attributedText.string.contains(" inline."))
        XCTAssertFalse(attributedText.string.contains("$e^{i\\pi}+1=0$"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownInlineChemistryLatexRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Water is $\\ce{H2O}$ and sulfate is $\\ce{SO4^2-}$.")

        XCTAssertTrue(attributedText.string.contains("Water is "))
        XCTAssertTrue(attributedText.string.contains(" and sulfate is "))
        XCTAssertFalse(attributedText.string.contains("\\ce{H2O}"))
        XCTAssertFalse(attributedText.string.contains("\\ce{SO4^2-}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 2)
    }

    func testMarkdownBareChemistryCommandRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Balanced reaction: \\ce{2H2 + O2 -> 2H2O}.")

        XCTAssertTrue(attributedText.string.contains("Balanced reaction: "))
        XCTAssertFalse(attributedText.string.contains("\\ce{2H2 + O2 -> 2H2O}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownExtensibleArrowLatexRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Catalyst $A \\xrightarrow[heat]{Pt} B$ done.")

        XCTAssertTrue(attributedText.string.contains("Catalyst "))
        XCTAssertTrue(attributedText.string.contains(" done."))
        XCTAssertFalse(attributedText.string.contains("\\xrightarrow[heat]{Pt}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownChemistryArrowLabelsRenderAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Labeled reaction: \\ce{A ->[H2O][heat] B}.")

        XCTAssertTrue(attributedText.string.contains("Labeled reaction: "))
        XCTAssertFalse(attributedText.string.contains("\\ce{A ->[H2O][heat] B}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownChemistryNuclideNotationRendersAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Nuclide: \\ce{^{227}_{90}Th+}.")

        XCTAssertTrue(attributedText.string.contains("Nuclide: "))
        XCTAssertFalse(attributedText.string.contains("\\ce{^{227}_{90}Th+}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
    }

    func testMarkdownChemistryPhysicalUnitsRenderAsInlineAttachment() throws {
        let attributedText = renderMarkdownText("Heat capacity: \\pu{75.3 J // mol K}; concentration: \\pu{1.2e-3 mol L-1}.")

        XCTAssertTrue(attributedText.string.contains("Heat capacity: "))
        XCTAssertFalse(attributedText.string.contains("\\pu{75.3 J // mol K}"))
        XCTAssertFalse(attributedText.string.contains("\\pu{1.2e-3 mol L-1}"))
        XCTAssertEqual(attributedText.textAttachmentCount, 2)
    }

    func testMarkdownChemistryComplexMhchemExamplesRenderAsInlineAttachments() throws {
        let attributedText = renderMarkdownText(
            "Examples: \\ce{Zn^2+ <=>[+ 2OH-][+ 2H+] Zn(OH)2 v}, \\ce{A\\bond{#}B}, \\ce{NaOH(aq,$\\infty$)}."
        )

        XCTAssertTrue(attributedText.string.contains("Examples: "))
        XCTAssertEqual(attributedText.textAttachmentCount, 3)
    }

    func testMarkdownEscapedDollarDoesNotStartInlineLatex() {
        let attributedText = renderMarkdownText("Price is \\$5 and math is $x+1$.")

        XCTAssertTrue(attributedText.string.contains("$5"))
        XCTAssertEqual(attributedText.textAttachmentCount, 1)
        XCTAssertTrue(attributedText.chatAccessibilityString.contains("Formula: x+1"))
    }

    func testMarkdownDisplayLatexRendersAsDedicatedBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Before

            $$
            \\frac{a}{b}=c
            $$

            After
            """
        )

        guard blocks.count == 3 else {
            XCTFail("Expected text, display math, and text blocks")
            return
        }
        guard case let .text(beforeText) = blocks[0] else {
            XCTFail("Expected leading text block")
            return
        }
        guard case let .mathBlock(mathBlock) = blocks[1] else {
            XCTFail("Expected display math block")
            return
        }
        guard case let .text(afterText) = blocks[2] else {
            XCTFail("Expected trailing text block")
            return
        }

        XCTAssertEqual(beforeText.string.trimmingCharacters(in: .whitespacesAndNewlines), "Before")
        XCTAssertEqual(mathBlock.latex, "\\frac{a}{b}=c")
        XCTAssertEqual(afterText.string.trimmingCharacters(in: .whitespacesAndNewlines), "After")
    }

    func testMarkdownDisplayChemistryLatexRendersAsDedicatedBlock() throws {
        let renderer = ChatMarkdownRenderer(traitCollection: markdownRendererTraits)
        let blocks = renderer.render(
            markdown: """
            Reaction

            $$
            \\ce{2H2 + O2 -> 2H2O}
            $$
            """
        )

        guard blocks.count == 2 else {
            XCTFail("Expected text and display chemistry blocks")
            return
        }
        guard case let .mathBlock(mathBlock) = blocks[1] else {
            XCTFail("Expected display chemistry block")
            return
        }

        XCTAssertEqual(mathBlock.latex, "\\ce{2H2 + O2 -> 2H2O}")
    }

    func testMarkdownMathSplitterKeepsMathInsideFenceWithInvalidClosingFence() {
        let segments = ChatMarkdownMathBlockSplitter.segments(
            in: """
            ```
            ``` not closed
            $$
            x
            $$
            """
        )

        XCTAssertEqual(segments.count, 1)
        guard case .markdown = segments[0] else {
            XCTFail("Expected invalid closing fence to keep display math inside fenced code")
            return
        }
    }
}
