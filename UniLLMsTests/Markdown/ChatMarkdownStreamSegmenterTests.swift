//
//  ChatMarkdownStreamSegmenterTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownStreamSegmenterTests: XCTestCase {
    func testMarkdownStreamSegmenterCompletesStableBlocksAndLeavesCurrentTail() {
        var segmenter = ChatMarkdownStreamSegmenter()

        var update = segmenter.append("# Title\n")
        XCTAssertEqual(update.completedSegments, ["# Title\n"])
        XCTAssertNil(update.currentSegment)

        update = segmenter.append("Intro")
        XCTAssertTrue(update.completedSegments.isEmpty)
        XCTAssertEqual(update.currentSegment, "Intro")

        update = segmenter.append("\n\n![Alt](https://example.com/image.png)\nNext")
        XCTAssertEqual(
            update.completedSegments,
            [
                "Intro\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "![Alt](https://example.com/image.png)\nNext")
    }

    func testMarkdownStreamSegmenterCompletesDisplayLatexBlock() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            $$
            x^2 + y^2 = z^2
            $$

            Next paragraph
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "$$\nx^2 + y^2 = z^2\n$$\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "Next paragraph")
    }

    func testMarkdownStreamSegmenterKeepsBlockQuoteAsOutermostSegment() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            > Outer
            > still quoted

            Next
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "> Outer\n> still quoted\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "Next")
    }

    func testMarkdownStreamSegmenterKeepsLazyBlockQuoteContinuationInQuoteSegment() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            > Outer
            lazy continuation

            Next
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "> Outer\nlazy continuation\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "Next")
    }

    func testMarkdownStreamSegmenterDoesNotLetHeadingBlockQuoteUseLazyContinuation() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            > # Title
            outside

            After
            """
        )

        XCTAssertEqual(update.completedSegments, ["> # Title\n", "outside\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotLetEmptyBlockQuoteUseLazyContinuation() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            >
            outside

            After
            """
        )

        XCTAssertEqual(update.completedSegments, [">\n", "outside\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterSeparatesBlankLineBetweenBlockQuotes() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            > First

            > Second
            """
        )

        XCTAssertEqual(update.completedSegments, ["> First\n"])
        XCTAssertEqual(update.currentSegment, "> Second")
    }

    func testMarkdownStreamSegmenterDoesNotTreatLazyLineAsBlockQuoteCodeFenceBody() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("> ```\ncode\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["> ```\n", "code\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotTreatLazyLineAsQuotedFenceBodyAfterQuotedCode() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("> ```swift\n> let value = 1\nlet outside = 2\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["> ```swift\n> let value = 1\n", "let outside = 2\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotTreatLazyLineAsQuotedListFenceBody() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("> - ```swift\n>   let value = 1\nlet outside = 2\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["> - ```swift\n>   let value = 1\n", "let outside = 2\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterCompletesTableWhenNextSegmentStarts() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | Feature | Count |
            | :-- | --: |
            | Tables | 2 |

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| Feature | Count |\n| :-- | --: |\n| Tables | 2 |\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterCompletesSingleColumnTableWhenNextSegmentStarts() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | A |
            | --- |
            | x |

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| A |\n| --- |\n| x |\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotTreatFourSpaceIndentedFenceAsTopLevelFence() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
                ```

            After
            """
        )

        XCTAssertEqual(update.completedSegments, ["    ```\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotTreatFourSpaceIndentedDisplayMathAsTopLevelMath() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
                $$

            After
            """
        )

        XCTAssertEqual(update.completedSegments, ["    $$\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotCloseDisplayMathWithIndentedDelimiter() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("$$\nx\n    $$\ntail")

        XCTAssertTrue(update.completedSegments.isEmpty)
        XCTAssertEqual(update.currentSegment, "$$\nx\n    $$\ntail")
    }

    func testMarkdownStreamSegmenterKeepsIndentedListDisplayMathInListSegment() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            - $$
              x
              $$

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "- $$\n  x\n  $$\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterKeepsNonPipeTableBodyRowsInTable() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | A | B |
            | --- | --- |
            | x | y |
            z

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| A | B |\n| --- | --- |\n| x | y |\nz\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotSplitMismatchedTableHeaderAndDelimiter() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | A | B |
            | --- |

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| A | B |\n| --- |\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterIgnoresPipeInsideHeaderCodeSpan() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | `A|B` |
            | --- |
            | value |

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| `A|B` |\n| --- |\n| value |\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotLetNonOneOrderedListInterruptParagraph() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            Intro
            2. still paragraph

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "Intro\n2. still paragraph\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotLetEmptyListItemInterruptParagraph() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            Intro
            *

            After
            """
        )

        XCTAssertEqual(update.completedSegments, ["Intro\n*\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotTreatSingleHyphenAsSetextUnderline() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            Intro
            -

            After
            """
        )

        XCTAssertEqual(update.completedSegments, ["Intro\n-\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterNormalizesSplitCRLFOnce() {
        var segmenter = ChatMarkdownStreamSegmenter()

        _ = segmenter.append("Intro\r")
        let update = segmenter.append("\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["Intro\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterKeepsHTMLDetailsAsOutermostSegment() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let detailsMarkdown = "<details>\n<summary>More</summary>\n\nInside **bold** body.\n\n</details>\n\nAfter"
        let update = segmenter.append(detailsMarkdown)

        XCTAssertEqual(
            update.completedSegments,
            ["<details>\n<summary>More</summary>\n\nInside **bold** body.\n\n</details>\n"]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotCompleteOpenHTMLDetailsBeforeClosingTag() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let detailsMarkdown = "<details>\n<summary>More</summary>\n\nInside **bold** body.\n"
        let update = segmenter.append(detailsMarkdown)

        XCTAssertTrue(update.completedSegments.isEmpty)
        XCTAssertEqual(update.currentSegment, detailsMarkdown)
    }

    func testMarkdownStreamSegmenterKeepsRawHTMLBlockUntilTerminatorAcrossBlankLines() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            <script>

            alert(1)
            </script>

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "<script>\n\nalert(1)\n</script>\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterEndsTableBeforeIndentedCodeBlock() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | A |
            | --- |
                code

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| A |\n| --- |\n",
                "    code\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterRecognizesTypeSevenClosingHTMLBlock() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("</script>\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["</script>\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterRecognizesSourceHTMLBlockTag() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("<source>\ntext\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["<source>\ntext\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterEndsTableBeforeTypeSevenHTMLBlock() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | A |
            | --- |
            <Warning>
            text

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| A |\n| --- |\n",
                "<Warning>\ntext\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterKeepsStandaloneImageLineInsideTableBody() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | A |
            | --- |
            ![Alt](https://example.com/image.png)

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| A |\n| --- |\n![Alt](https://example.com/image.png)\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterKeepsMalformedHTMLTagInsideTableBody() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append(
            """
            | A |
            | --- |
            </a href="https://example.com">

            After
            """
        )

        XCTAssertEqual(
            update.completedSegments,
            [
                "| A |\n| --- |\n</a href=\"https://example.com\">\n"
            ]
        )
        XCTAssertEqual(update.currentSegment, "After")
    }

    func testMarkdownStreamSegmenterDoesNotTreatInlineDetailsTextAsHTMLBlock() {
        var segmenter = ChatMarkdownStreamSegmenter()

        let update = segmenter.append("The <details> tag is literal text.\n\nAfter")

        XCTAssertEqual(update.completedSegments, ["The <details> tag is literal text.\n"])
        XCTAssertEqual(update.currentSegment, "After")
    }
}
