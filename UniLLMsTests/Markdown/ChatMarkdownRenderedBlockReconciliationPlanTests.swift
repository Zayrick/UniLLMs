//
//  ChatMarkdownRenderedBlockReconciliationPlanTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

final class ChatMarkdownRenderedBlockReconciliationPlanTests: XCTestCase {
    func testPlanReusesMatchingRecord() {
        let block = ChatMarkdownRenderedBlock.text(NSAttributedString(string: "Hello"))
        let record = makeRecord(for: block)

        let plan = ChatMarkdownRenderedBlockReconciliationPlan(
            blocks: [block],
            currentRecords: [record],
            startingAt: 3,
            allowsIdentityChange: false
        )

        XCTAssertEqual(plan.operations.count, 1)
        guard case let .reuse(reuse) = plan.operations[0] else {
            XCTFail("Expected reuse operation.")
            return
        }

        XCTAssertIdentical(reuse.record.view, record.view)
        XCTAssertEqual(reuse.desiredIndex, 3)
        XCTAssertTrue(plan.removedRecords.isEmpty)
    }

    func testPlanInsertsWhenIdentityChangesWithoutPermission() {
        let original = ChatMarkdownRenderedBlock.text(NSAttributedString(string: "Hello"))
        let updated = ChatMarkdownRenderedBlock.text(NSAttributedString(string: "Hello!"))
        let record = makeRecord(for: original)

        let plan = ChatMarkdownRenderedBlockReconciliationPlan(
            blocks: [updated],
            currentRecords: [record],
            startingAt: 0,
            allowsIdentityChange: false
        )

        XCTAssertEqual(plan.operations.count, 1)
        guard case let .insert(insertion) = plan.operations[0] else {
            XCTFail("Expected insert operation.")
            return
        }

        XCTAssertEqual(insertion.desiredIndex, 0)
        XCTAssertEqual(plan.removedRecords.count, 1)
        XCTAssertIdentical(plan.removedRecords[0].view, record.view)
    }

    func testPlanReusesWhenIdentityChangeIsAllowed() {
        let original = ChatMarkdownRenderedBlock.text(NSAttributedString(string: "**bo"))
        let updated = ChatMarkdownRenderedBlock.text(NSAttributedString(string: "bold"))
        let record = makeRecord(for: original)

        let plan = ChatMarkdownRenderedBlockReconciliationPlan(
            blocks: [updated],
            currentRecords: [record],
            startingAt: 1,
            allowsIdentityChange: true
        )

        XCTAssertEqual(plan.operations.count, 1)
        guard case let .reuse(reuse) = plan.operations[0] else {
            XCTFail("Expected reuse operation.")
            return
        }

        XCTAssertIdentical(reuse.record.view, record.view)
        XCTAssertEqual(reuse.desiredIndex, 1)
        XCTAssertTrue(plan.removedRecords.isEmpty)
    }

    func testPlanRebuildsRemainingRecordsAfterFirstMismatch() {
        let firstOriginal = ChatMarkdownRenderedBlock.text(NSAttributedString(string: "A"))
        let secondOriginal = ChatMarkdownRenderedBlock.text(NSAttributedString(string: "B"))
        let firstRecord = makeRecord(for: firstOriginal)
        let secondRecord = makeRecord(for: secondOriginal)

        let plan = ChatMarkdownRenderedBlockReconciliationPlan(
            blocks: [
                .mathBlock(ChatMarkdownMathBlock(latex: "x")),
                secondOriginal
            ],
            currentRecords: [firstRecord, secondRecord],
            startingAt: 0,
            allowsIdentityChange: false
        )

        XCTAssertEqual(plan.operations.count, 2)
        guard case .insert = plan.operations[0],
              case .insert = plan.operations[1] else {
            XCTFail("Expected first mismatch to rebuild remaining records.")
            return
        }
        XCTAssertEqual(plan.removedRecords.count, 2)
        XCTAssertIdentical(plan.removedRecords[0].view, firstRecord.view)
        XCTAssertIdentical(plan.removedRecords[1].view, secondRecord.view)
    }

    func testPlanSkipsEmptyTextBlocks() {
        let record = makeRecord(
            for: .text(NSAttributedString(string: "Existing"))
        )

        let plan = ChatMarkdownRenderedBlockReconciliationPlan(
            blocks: [.text(NSAttributedString(string: ""))],
            currentRecords: [record],
            startingAt: 0,
            allowsIdentityChange: false
        )

        XCTAssertTrue(plan.operations.isEmpty)
        XCTAssertEqual(plan.removedRecords.count, 1)
        XCTAssertIdentical(plan.removedRecords[0].view, record.view)
    }

    private func makeRecord(
        for block: ChatMarkdownRenderedBlock
    ) -> ChatMarkdownRenderedBlockViewRecord {
        ChatMarkdownRenderedBlockViewRecord(
            view: UIView(),
            kind: block.viewKind,
            identity: ChatMarkdownRenderedBlockViewIdentity(block)
        )
    }
}
