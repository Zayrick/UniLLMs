//
//  ChatMarkdownTextFadeMaskPlanTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownTextFadeMaskPlanTests: XCTestCase {
    func testFadeFramesClipChangedAndUsedRectsToBounds() {
        let plan = ChatMarkdownTextFadeMaskPlan(
            bounds: CGRect(x: 0.0, y: 0.0, width: 100.0, height: 40.0),
            minimumLayerSize: 0.5,
            fragments: [
                ChatMarkdownTextFadeMaskPlan.LineFragment(
                    changedRect: CGRect(x: 80.0, y: 10.0, width: 50.0, height: 20.0),
                    lineFrame: CGRect(x: 0.0, y: 10.0, width: 120.0, height: 20.0),
                    usedFrame: CGRect(x: 0.0, y: 10.0, width: 120.0, height: 20.0)
                )
            ]
        )

        XCTAssertEqual(
            plan.fadeFrames,
            [CGRect(x: 80.0, y: 10.0, width: 20.0, height: 20.0)]
        )
        XCTAssertEqual(
            plan.opaqueFrames,
            [
                CGRect(x: 0.0, y: 0.0, width: 100.0, height: 10.0),
                CGRect(x: 0.0, y: 10.0, width: 80.0, height: 20.0)
            ]
        )
    }

    func testFadeFrameFallsBackToUsedFrameWhenChangedRectIsInvalid() {
        let plan = ChatMarkdownTextFadeMaskPlan(
            bounds: CGRect(x: 0.0, y: 0.0, width: 100.0, height: 40.0),
            minimumLayerSize: 0.5,
            fragments: [
                ChatMarkdownTextFadeMaskPlan.LineFragment(
                    changedRect: .null,
                    lineFrame: CGRect(x: 0.0, y: 8.0, width: 100.0, height: 18.0),
                    usedFrame: CGRect(x: 12.0, y: 8.0, width: 40.0, height: 18.0)
                )
            ]
        )

        XCTAssertEqual(
            plan.fadeFrames,
            [CGRect(x: 12.0, y: 8.0, width: 40.0, height: 18.0)]
        )
        XCTAssertEqual(
            plan.opaqueFrames,
            [
                CGRect(x: 0.0, y: 0.0, width: 100.0, height: 8.0),
                CGRect(x: 0.0, y: 8.0, width: 12.0, height: 18.0)
            ]
        )
    }

    func testPlanFiltersFramesThatAreTooSmallToRender() {
        let plan = ChatMarkdownTextFadeMaskPlan(
            bounds: CGRect(x: 0.0, y: 0.0, width: 100.0, height: 40.0),
            minimumLayerSize: 0.5,
            fragments: [
                ChatMarkdownTextFadeMaskPlan.LineFragment(
                    changedRect: CGRect(x: 99.75, y: 0.0, width: 0.25, height: 40.0),
                    lineFrame: CGRect(x: 0.0, y: 0.0, width: 100.0, height: 40.0),
                    usedFrame: CGRect(x: 0.0, y: 0.0, width: 100.0, height: 40.0)
                )
            ]
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.fadeFrames.isEmpty)
        XCTAssertEqual(
            plan.opaqueFrames,
            [CGRect(x: 0.0, y: 0.0, width: 99.75, height: 40.0)]
        )
    }
}
