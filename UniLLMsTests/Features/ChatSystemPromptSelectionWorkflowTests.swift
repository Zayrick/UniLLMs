//
//  ChatSystemPromptSelectionWorkflowTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatSystemPromptSelectionWorkflowTests: XCTestCase {
    func testDisplayUsesPromptDisplayTitle() {
        let prompt = makePrompt(title: "  Travel coach  ")

        let display = ChatSystemPromptSelectionWorkflow.display(from: prompt)

        XCTAssertEqual(display?.id, prompt.id)
        XCTAssertEqual(display?.title, "Travel coach")
    }

    func testDisplayReturnsNilWithoutPrompt() {
        XCTAssertNil(ChatSystemPromptSelectionWorkflow.display(from: nil))
    }

    func testSelectingPromptUpdatesRuntimeAndComposerDisplay() {
        let prompt = makePrompt(title: "Assistant style")
        var selectedPrompt: SystemPromptRecord?
        var selectedPromptID: UUID?
        var displayedPrompt: ChatSelectedSystemPromptDisplay?
        let workflow = makeWorkflow(
            selectedPrompt: { selectedPrompt },
            selectSystemPrompt: { id in
                selectedPromptID = id
                selectedPrompt = prompt
            },
            setComposerDisplay: { displayedPrompt = $0 }
        )

        workflow.select(prompt)

        XCTAssertEqual(selectedPromptID, prompt.id)
        XCTAssertEqual(displayedPrompt?.id, prompt.id)
        XCTAssertEqual(displayedPrompt?.title, "Assistant style")
    }

    func testClearingPromptUpdatesRuntimeAndComposerDisplay() {
        var selectedPrompt: SystemPromptRecord? = makePrompt(title: "Assistant style")
        var didClear = false
        var displayedPrompt: ChatSelectedSystemPromptDisplay? = ChatSelectedSystemPromptDisplay(
            id: UUID(),
            title: "Previous"
        )
        let workflow = makeWorkflow(
            selectedPrompt: { selectedPrompt },
            clearSystemPrompt: {
                didClear = true
                selectedPrompt = nil
            },
            setComposerDisplay: { displayedPrompt = $0 }
        )

        workflow.clearSelection()

        XCTAssertTrue(didClear)
        XCTAssertNil(displayedPrompt)
    }

    func testSelectionPresentationPassesSelectedIDAndRoutesCallbacks() throws {
        let selectedID = UUID()
        let prompt = makePrompt(title: "Prompt")
        let rootViewController = UIViewController()
        let wrappedViewController = UIViewController()
        var capturedSelectedID: UUID?
        var capturedSelect: (@MainActor (SystemPromptRecord) -> Void)?
        var capturedClear: (@MainActor () -> Void)?
        var selectedPromptID: UUID?
        var didClear = false
        let workflow = makeWorkflow(
            selectedSystemPromptID: { selectedID },
            selectSystemPrompt: { selectedPromptID = $0 },
            clearSystemPrompt: { didClear = true },
            buildPromptList: { selectedID, onSelect, onClear in
                capturedSelectedID = selectedID
                capturedSelect = onSelect
                capturedClear = onClear
                return rootViewController
            },
            wrapForPresentation: { root in
                XCTAssertTrue(root === rootViewController)
                return wrappedViewController
            }
        )

        let presentation = workflow.makeSelectionViewController()
        capturedSelect?(prompt)
        capturedClear?()

        XCTAssertTrue(presentation === wrappedViewController)
        XCTAssertEqual(capturedSelectedID, selectedID)
        XCTAssertEqual(selectedPromptID, prompt.id)
        XCTAssertTrue(didClear)
    }

    private func makeWorkflow(
        selectedSystemPromptID: @escaping () -> UUID? = { nil },
        selectedPrompt: @escaping () -> SystemPromptRecord? = { nil },
        selectSystemPrompt: @escaping (UUID) -> Void = { _ in },
        clearSystemPrompt: @escaping () -> Void = {},
        setComposerDisplay: @escaping (ChatSelectedSystemPromptDisplay?) -> Void = { _ in },
        buildPromptList: @escaping ChatSystemPromptSelectionWorkflow.PromptListBuilder = { _, _, _ in UIViewController() },
        wrapForPresentation: @escaping ChatSystemPromptSelectionWorkflow.PresentationWrapper = { $0 }
    ) -> ChatSystemPromptSelectionWorkflow {
        ChatSystemPromptSelectionWorkflow(
            selectedSystemPromptID: selectedSystemPromptID,
            selectedSystemPrompt: selectedPrompt,
            selectSystemPrompt: selectSystemPrompt,
            clearSystemPrompt: clearSystemPrompt,
            setComposerDisplay: setComposerDisplay,
            buildPromptList: buildPromptList,
            wrapForPresentation: wrapForPresentation
        )
    }

    private func makePrompt(
        id: UUID = UUID(),
        title: String
    ) -> SystemPromptRecord {
        SystemPromptRecord(
            id: id,
            title: title,
            content: "Use this style.",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
