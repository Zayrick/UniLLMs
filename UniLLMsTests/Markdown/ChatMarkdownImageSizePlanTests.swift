//
//  ChatMarkdownImageSizePlanTests.swift
//  UniLLMsTests
//

import CoreGraphics
import XCTest
@testable import UniLLMs

final class ChatMarkdownImageSizePlanTests: XCTestCase {
    func testPlanUsesPlaceholderSizeWhenImageIsMissingOrInvalid() {
        XCTAssertEqual(
            ChatMarkdownImageSizePlan(imageSize: nil, maxWidth: 240.0).size,
            CGSize(width: 240.0, height: 150.0)
        )
        XCTAssertEqual(
            ChatMarkdownImageSizePlan(imageSize: CGSize(width: 0.0, height: 100.0), maxWidth: 240.0).size,
            CGSize(width: 240.0, height: 150.0)
        )
        XCTAssertEqual(
            ChatMarkdownImageSizePlan(imageSize: CGSize(width: 100.0, height: 0.0), maxWidth: 0.0).size,
            CGSize(width: 1.0, height: 150.0)
        )
    }

    func testPlanKeepsNaturalImageSizeWhenItFits() {
        let plan = ChatMarkdownImageSizePlan(
            imageSize: CGSize(width: 200.0, height: 100.0),
            maxWidth: 300.0
        )

        XCTAssertEqual(plan.size, CGSize(width: 200.0, height: 100.0))
    }

    func testPlanScalesImageDownToAvailableWidth() {
        let plan = ChatMarkdownImageSizePlan(
            imageSize: CGSize(width: 400.0, height: 200.0),
            maxWidth: 100.0
        )

        XCTAssertEqual(plan.size, CGSize(width: 100.0, height: 50.0))
    }

    func testPlanCapsImageHeightAndRecomputesWidth() {
        let plan = ChatMarkdownImageSizePlan(
            imageSize: CGSize(width: 100.0, height: 1000.0),
            maxWidth: 500.0
        )

        XCTAssertEqual(plan.size, CGSize(width: 40.0, height: 400.0))
    }

    func testPlanCeilsFractionalScaledSizes() {
        let plan = ChatMarkdownImageSizePlan(
            imageSize: CGSize(width: 3.0, height: 2.0),
            maxWidth: 2.0
        )

        XCTAssertEqual(plan.size, CGSize(width: 2.0, height: 2.0))
    }
}
