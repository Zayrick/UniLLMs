//
//  ChatSideMenuPageGeometryTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

final class ChatSideMenuPageGeometryTests: XCTestCase {
    func testOpenGeometryAppliesRevealAndVisualState() {
        let geometry = ChatSideMenuPageGeometry.make(
            isOpen: true,
            pageWidth: 400.0,
            revealRatio: 0.8,
            openPageOpacity: 0.72,
            openCornerRadius: 32.0,
            openShadowOpacity: 0.18
        )

        XCTAssertEqual(geometry.pageTranslationX, 320.0)
        XCTAssertEqual(geometry.pageAlpha, 0.72)
        XCTAssertEqual(geometry.pageCornerRadius, 32.0)
        XCTAssertTrue(geometry.pageMasksToBounds)
        XCTAssertEqual(geometry.sideMenuAlpha, 1.0)
        XCTAssertEqual(geometry.dismissControlAlpha, 1.0)
        XCTAssertEqual(geometry.shadowOpacity, 0.18)
    }

    func testClosedGeometryRestoresPageState() {
        let geometry = ChatSideMenuPageGeometry.make(
            isOpen: false,
            pageWidth: 400.0,
            revealRatio: 0.8,
            openPageOpacity: 0.72,
            openCornerRadius: 32.0,
            openShadowOpacity: 0.18
        )

        XCTAssertEqual(geometry.pageTranslationX, 0.0)
        XCTAssertEqual(geometry.pageAlpha, 1.0)
        XCTAssertEqual(geometry.pageCornerRadius, 0.0)
        XCTAssertFalse(geometry.pageMasksToBounds)
        XCTAssertEqual(geometry.sideMenuAlpha, 0.0)
        XCTAssertEqual(geometry.dismissControlAlpha, 0.0)
        XCTAssertEqual(geometry.shadowOpacity, 0.0)
    }
}
