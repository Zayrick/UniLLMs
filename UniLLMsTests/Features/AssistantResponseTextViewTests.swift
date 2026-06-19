//
//  AssistantResponseTextViewTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

final class AssistantResponseTextViewTests: XCTestCase {
    @MainActor
    func testAssistantResponseRendersTimelineThroughSingleStreamingContentView() {
        let responseView = AssistantResponseTextView()
        responseView.frame = CGRect(x: 0.0, y: 0.0, width: 320.0, height: 480.0)
        var layoutInvalidationCount = 0
        responseView.onLayoutInvalidated = {
            layoutInvalidationCount += 1
        }

        let toolCall = ChatToolCall(
            id: "call_1",
            toolID: "weather.search",
            arguments: "{}",
            displayName: "Weather Search"
        )
        responseView.appendStoredReasoning("Need data.")
        responseView.appendDisplayPart(.toolEvent(.started(toolCall)))
        responseView.appendDisplayPart(.toolEvent(.completed(toolCall, result: "Sunny.")))
        responseView.appendStoredRawText("Done.")
        responseView.finishStreamingContent()
        responseView.layoutIfNeeded()

        XCTAssertEqual(responseView.recursiveContentViews.count, 1)
        XCTAssertGreaterThan(layoutInvalidationCount, 0)
    }
}

private extension UIView {
    var recursiveContentViews: [StreamingContentView] {
        let directContentViews = subviews.compactMap { $0 as? StreamingContentView }
        return directContentViews + subviews.flatMap { $0.recursiveContentViews }
    }
}
