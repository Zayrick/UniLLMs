//
//  ThinkingSectionViewTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class ThinkingSectionViewTests: XCTestCase {
    @MainActor
    func testThinkingSectionHeaderKeepsProcessingStatusAndShowsFinishedCounts() {
        let section = ThinkingSectionView()

        XCTAssertEqual(section.firstLabelText, "Processing")

        section.appendReasoning("Need data.")
        section.appendToolInvocation(
            callID: "call_1",
            displayName: "Weather Search",
            state: .running
        )

        XCTAssertEqual(section.firstLabelText, "Processing")

        section.appendToolInvocation(
            callID: "call_1",
            displayName: "Weather Search",
            state: .completed
        )
        section.appendReasoning("Use the result.")
        section.setThinking(false, animated: false)

        XCTAssertEqual(section.firstLabelText, "2 reasoning steps, 1 tool call")
        XCTAssertFalse(section.containsLabelText("Thought process"))
    }

    @MainActor
    func testThinkingSectionFinishedHeaderOmitsZeroCounts() {
        let reasoningOnlySection = ThinkingSectionView()
        reasoningOnlySection.appendReasoning("Need data.")
        reasoningOnlySection.setThinking(false, animated: false)

        XCTAssertEqual(reasoningOnlySection.firstLabelText, "1 reasoning step")

        let toolOnlySection = ThinkingSectionView()
        toolOnlySection.appendToolInvocation(
            callID: "call_1",
            displayName: "Weather Search",
            state: .completed
        )
        toolOnlySection.setThinking(false, animated: false)

        XCTAssertEqual(toolOnlySection.firstLabelText, "1 tool call")

        let emptySection = ThinkingSectionView()
        emptySection.setThinking(false, animated: false)

        XCTAssertTrue(emptySection.isHidden)
    }
}

private extension UIView {
    var firstLabelText: String? {
        recursiveLabels.first?.text
    }

    func containsLabelText(_ text: String) -> Bool {
        recursiveLabels.contains { $0.text == text }
    }

    var recursiveLabels: [UILabel] {
        let directLabels = subviews.compactMap { $0 as? UILabel }
        return directLabels + subviews.flatMap { $0.recursiveLabels }
    }
}
