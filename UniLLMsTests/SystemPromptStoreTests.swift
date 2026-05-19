//
//  SystemPromptStoreTests.swift
//  UniLLMsTests
//
//  Covers system prompt persistence behavior.
//  Created by Codex on 2026/5/19.
//

import Foundation
import XCTest
@testable import UniLLMs

final class SystemPromptStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: UserDefaultsSystemPromptStore!
    private var manager: SystemPromptManager!

    override func setUpWithError() throws {
        suiteName = "SystemPromptStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = UserDefaultsSystemPromptStore(defaults: defaults, storageKey: "systemPrompts")
        manager = SystemPromptManager(store: store)
    }

    override func tearDownWithError() throws {
        if let defaults = defaults, let suiteName = suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        store = nil
        manager = nil
    }

    func testSavingPromptPersistsTitleAndContent() throws {
        let prompt = makePrompt(title: "Translation Assistant", content: "Always answer in Chinese.")

        manager.savePrompt(prompt)

        let reloadedStore = UserDefaultsSystemPromptStore(defaults: defaults, storageKey: "systemPrompts")
        let reloadedPrompt = try XCTUnwrap(reloadedStore.loadPrompts().first)
        XCTAssertEqual(reloadedPrompt, prompt)
    }

    func testUpdatingPromptReplacesMatchingUUID() throws {
        let prompt = makePrompt(title: "Translation Assistant", content: "Always answer in Chinese.")
        var updatedPrompt = prompt
        updatedPrompt.title = "Code Review"
        updatedPrompt.content = "Review for correctness first."
        updatedPrompt.updatedAt = Date(timeIntervalSince1970: 2)

        manager.savePrompt(prompt)
        manager.savePrompt(updatedPrompt)

        XCTAssertEqual(manager.savedPrompts(), [updatedPrompt])
    }

    func testDeletingPromptRemovesMatchingUUIDOnly() throws {
        let first = makePrompt(
            title: "Translation Assistant",
            content: "Always answer in Chinese."
        )
        let second = makePrompt(
            title: "Code Review",
            content: "Review for correctness first."
        )
        manager.savePrompt(first)
        manager.savePrompt(second)

        manager.deletePrompt(id: first.id)

        XCTAssertEqual(manager.savedPrompts(), [second])
    }

    func testDraftDoesNotPersistUntilSaved() {
        let draft = manager.makePromptDraft()

        XCTAssertTrue(manager.savedPrompts().isEmpty)

        manager.savePrompt(draft)

        XCTAssertEqual(manager.savedPrompts(), [draft])
    }

    private func makePrompt(
        id: UUID = UUID(),
        title: String,
        content: String
    ) -> SystemPromptRecord {
        SystemPromptRecord(
            id: id,
            title: title,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
