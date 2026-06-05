//
//  ChatAttachmentImportErrorPresentationTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatAttachmentImportErrorPresentationTests: XCTestCase {
    func testMakeReturnsNilForEmptyErrors() {
        XCTAssertNil(ChatAttachmentImportErrorPresentation.make(for: []))
    }

    func testMakeReturnsNilWhenAllMessagesAreEmpty() {
        let error = EmptyLocalizedDescriptionError()

        XCTAssertNil(ChatAttachmentImportErrorPresentation.make(for: [error]))
    }

    func testMakeCombinesAllNonEmptyMessagesIntoSinglePresentation() {
        let firstError = NSError(domain: "ChatAttachmentImportErrorPresentationTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "First"
        ])
        let emptyError = EmptyLocalizedDescriptionError()
        let secondError = NSError(domain: "ChatAttachmentImportErrorPresentationTests", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Second"
        ])

        let presentation = ChatAttachmentImportErrorPresentation.make(for: [
            firstError,
            emptyError,
            secondError
        ])

        XCTAssertEqual(presentation?.message, "First\nSecond")
    }
}

private struct EmptyLocalizedDescriptionError: LocalizedError {
    var errorDescription: String? {
        ""
    }
}
