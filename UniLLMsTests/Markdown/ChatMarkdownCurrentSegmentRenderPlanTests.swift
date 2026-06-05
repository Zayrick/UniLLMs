//
//  ChatMarkdownCurrentSegmentRenderPlanTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatMarkdownCurrentSegmentRenderPlanTests: XCTestCase {
    func testPlanFiltersImagesAndEmptyTextBlocks() {
        let plan = ChatMarkdownCurrentSegmentRenderPlan(
            blocks: [
                textBlock(""),
                imageBlock(),
                textBlock("Visible")
            ]
        )

        XCTAssertEqual(plan.blocks.count, 1)
        XCTAssertEqual(text(in: plan.blocks[0]), "Visible")
    }

    func testPlanMarksCodeBlocksAsStreaming() {
        let plan = ChatMarkdownCurrentSegmentRenderPlan(
            blocks: [
                .codeBlock(
                    ChatMarkdownCodeBlock(
                        code: "let value = 1",
                        language: "swift",
                        isStreaming: false
                    )
                )
            ]
        )

        guard case let .codeBlock(codeBlock) = plan.blocks.first else {
            XCTFail("Expected code block.")
            return
        }

        XCTAssertEqual(codeBlock.code, "let value = 1")
        XCTAssertEqual(codeBlock.language, "swift")
        XCTAssertTrue(codeBlock.isStreaming)
    }

    func testPlanFiltersNestedContainersWhenAllChildrenAreUnrenderable() {
        let plan = ChatMarkdownCurrentSegmentRenderPlan(
            blocks: [
                .blockQuote(
                    ChatMarkdownBlockQuoteBlock(
                        children: [
                            imageBlock(),
                            textBlock("")
                        ]
                    )
                ),
                .list(
                    ChatMarkdownListBlock(
                        isOrdered: false,
                        items: [
                            ChatMarkdownListItemBlock(
                                marker: .text("-"),
                                children: [
                                    imageBlock()
                                ]
                            )
                        ]
                    )
                )
            ]
        )

        XCTAssertTrue(plan.blocks.isEmpty)
    }

    func testPlanRecursesThroughBlockQuotesAndLists() {
        let plan = ChatMarkdownCurrentSegmentRenderPlan(
            blocks: [
                .blockQuote(
                    ChatMarkdownBlockQuoteBlock(
                        children: [
                            imageBlock(),
                            .codeBlock(ChatMarkdownCodeBlock(code: "print(value)", language: nil)),
                            .list(
                                ChatMarkdownListBlock(
                                    isOrdered: false,
                                    items: [
                                        ChatMarkdownListItemBlock(
                                            marker: .text("skip"),
                                            children: [imageBlock()]
                                        ),
                                        ChatMarkdownListItemBlock(
                                            marker: .checkbox(isChecked: false),
                                            children: [textBlock("Task")]
                                        )
                                    ]
                                )
                            )
                        ]
                    )
                )
            ]
        )

        guard case let .blockQuote(blockQuoteBlock) = plan.blocks.first else {
            XCTFail("Expected block quote.")
            return
        }
        XCTAssertEqual(blockQuoteBlock.children.count, 2)

        guard case let .codeBlock(codeBlock) = blockQuoteBlock.children[0] else {
            XCTFail("Expected streaming code block.")
            return
        }
        XCTAssertTrue(codeBlock.isStreaming)

        guard case let .list(listBlock) = blockQuoteBlock.children[1] else {
            XCTFail("Expected filtered list.")
            return
        }
        XCTAssertEqual(listBlock.items.count, 1)
        XCTAssertEqual(listBlock.items[0].marker, .checkbox(isChecked: false))
        XCTAssertEqual(text(in: listBlock.items[0].children[0]), "Task")
    }

    func testPlanKeepsMathAndDetailsBlocks() {
        let plan = ChatMarkdownCurrentSegmentRenderPlan(
            blocks: [
                .mathBlock(ChatMarkdownMathBlock(latex: "x^2")),
                .details(
                    ChatMarkdownDetailsBlock(
                        summary: "More",
                        isOpen: true,
                        children: [imageBlock()]
                    )
                )
            ]
        )

        XCTAssertEqual(plan.blocks.count, 2)
        guard case let .mathBlock(mathBlock) = plan.blocks[0] else {
            XCTFail("Expected math block.")
            return
        }
        XCTAssertEqual(mathBlock.latex, "x^2")

        guard case let .details(detailsBlock) = plan.blocks[1] else {
            XCTFail("Expected details block.")
            return
        }
        XCTAssertEqual(detailsBlock.summary, "More")
        XCTAssertTrue(detailsBlock.isOpen)
        XCTAssertEqual(detailsBlock.children.count, 1)
    }

    private func textBlock(_ string: String) -> ChatMarkdownRenderedBlock {
        .text(NSAttributedString(string: string))
    }

    private func imageBlock() -> ChatMarkdownRenderedBlock {
        .image(
            ChatMarkdownImageBlock(
                source: "https://example.com/image.png",
                altText: "Diagram"
            )
        )
    }

    private func text(in block: ChatMarkdownRenderedBlock) -> String? {
        guard case let .text(attributedText) = block else {
            return nil
        }

        return attributedText.string
    }
}
