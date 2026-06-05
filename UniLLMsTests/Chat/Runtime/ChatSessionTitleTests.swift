//
//  ChatSessionTitleTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class ChatSessionTitleTests: XCTestCase {
    func testTitleUsesSingleLineTrimmedPrompt() {
        XCTAssertEqual(
            ChatSessionTitle.make(
                prompt: "  First line\nSecond line  ",
                emptyConversationTitle: "New Chat",
                attachmentFallbackTitle: "Attachment"
            ),
            "First line Second line"
        )
    }

    func testTitleUsesFirstAttachmentFilenameWhenPromptIsEmpty() {
        XCTAssertEqual(
            ChatSessionTitle.make(
                prompt: " \n ",
                attachments: [
                    ChatAttachment(
                        kind: .file,
                        filename: " document.pdf ",
                        contentType: "application/pdf",
                        relativePath: "attachments/document.pdf"
                    )
                ],
                emptyConversationTitle: "New Chat",
                attachmentFallbackTitle: "Attachment"
            ),
            "document.pdf"
        )
    }

    func testTitleUsesAttachmentFallbackWhenPromptAndFilenameAreEmpty() {
        XCTAssertEqual(
            ChatSessionTitle.make(
                prompt: "",
                attachments: [
                    ChatAttachment(
                        kind: .file,
                        filename: " ",
                        contentType: "application/octet-stream",
                        relativePath: "attachments/file"
                    )
                ],
                emptyConversationTitle: "New Chat",
                attachmentFallbackTitle: "Attachment"
            ),
            "Attachment"
        )
    }

    func testTitleUsesEmptyConversationTitleWhenPromptAndAttachmentsAreEmpty() {
        XCTAssertEqual(
            ChatSessionTitle.make(
                prompt: "",
                emptyConversationTitle: "New Chat",
                attachmentFallbackTitle: "Attachment"
            ),
            "New Chat"
        )
    }
}
