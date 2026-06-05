//
//  ChatAttachmentPreviewControllerTests.swift
//  UniLLMsTests
//

import XCTest
import QuickLook
@testable import UniLLMs

final class ChatAttachmentPreviewControllerTests: XCTestCase {
    func testMissingFileReturnsFileMissingAndNoPreviewItems() {
        let controller = ChatAttachmentPreviewController(
            fileURL: { _ in nil },
            canPreview: { _ in true }
        )

        XCTAssertEqual(
            controller.preparePreview(for: Self.attachment(filename: "missing.pdf")),
            .fileMissing
        )
        XCTAssertEqual(controller.previewItemCount, 0)
    }

    func testUnsupportedFileReturnsPreviewUnavailableAndNoPreviewItems() {
        let fileURL = URL(fileURLWithPath: "/tmp/unsupported.bin")
        let controller = ChatAttachmentPreviewController(
            fileURL: { _ in fileURL },
            canPreview: { _ in false }
        )

        XCTAssertEqual(
            controller.preparePreview(for: Self.attachment(filename: "unsupported.bin")),
            .previewUnavailable
        )
        XCTAssertEqual(controller.previewItemCount, 0)
    }

    func testSupportedFileStoresPreviewItemWithTitleAndURL() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let attachment = Self.attachment(filename: "Report")
        let controller = ChatAttachmentPreviewController(
            fileURL: { _ in fileURL },
            canPreview: { item in
                item.previewItemURL == fileURL && item.previewItemTitle == "Report"
            }
        )

        XCTAssertEqual(controller.preparePreview(for: attachment), .ready)
        XCTAssertEqual(controller.previewItemCount, 1)

        let previewItem = controller.previewItem(at: 0)
        XCTAssertEqual(previewItem.previewItemURL, fileURL)
        XCTAssertEqual(previewItem.previewItemTitle, "Report")
    }

    func testClearPreviewRemovesCurrentItem() {
        let controller = ChatAttachmentPreviewController(
            fileURL: { _ in URL(fileURLWithPath: "/tmp/report.pdf") },
            canPreview: { _ in true }
        )

        XCTAssertEqual(controller.preparePreview(for: Self.attachment(filename: "Report")), .ready)
        controller.clearPreview()

        XCTAssertEqual(controller.previewItemCount, 0)
    }

    func testPreparingMissingFileClearsPreviouslyReadyPreview() {
        let controller = ChatAttachmentPreviewController(
            fileURL: { attachment in
                attachment.filename == "Report"
                    ? URL(fileURLWithPath: "/tmp/report.pdf")
                    : nil
            },
            canPreview: { _ in true }
        )

        XCTAssertEqual(controller.preparePreview(for: Self.attachment(filename: "Report")), .ready)
        XCTAssertEqual(controller.preparePreview(for: Self.attachment(filename: "Missing")), .fileMissing)

        XCTAssertEqual(controller.previewItemCount, 0)
    }

    func testPreparingUnsupportedFileClearsPreviouslyReadyPreview() {
        let controller = ChatAttachmentPreviewController(
            fileURL: { attachment in URL(fileURLWithPath: "/tmp/\(attachment.filename)") },
            canPreview: { item in
                item.previewItemTitle == "Report"
            }
        )

        XCTAssertEqual(controller.preparePreview(for: Self.attachment(filename: "Report")), .ready)
        XCTAssertEqual(
            controller.preparePreview(for: Self.attachment(filename: "Unsupported")),
            .previewUnavailable
        )

        XCTAssertEqual(controller.previewItemCount, 0)
    }

    func testPreparingNewReadyPreviewReplacesPreviousItem() {
        let controller = ChatAttachmentPreviewController(
            fileURL: { attachment in URL(fileURLWithPath: "/tmp/\(attachment.filename)") },
            canPreview: { _ in true }
        )

        XCTAssertEqual(controller.preparePreview(for: Self.attachment(filename: "First.pdf")), .ready)
        XCTAssertEqual(controller.preparePreview(for: Self.attachment(filename: "Second.pdf")), .ready)

        let previewItem = controller.previewItem(at: 0)
        XCTAssertEqual(previewItem.previewItemURL, URL(fileURLWithPath: "/tmp/Second.pdf"))
        XCTAssertEqual(previewItem.previewItemTitle, "Second.pdf")
    }

    private static func attachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            kind: .file,
            filename: filename,
            contentType: "application/pdf",
            relativePath: filename
        )
    }
}
