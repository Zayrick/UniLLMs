//
//  LLMsProviderAttachmentPayloadTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

final class LLMsProviderAttachmentPayloadTests: XCTestCase {
    func testPayloadLoaderBuildsProviderPayload() throws {
        let attachment = Self.attachment(contentType: "")
        let loader = LLMsProviderAttachmentPayloadLoader(
            dataLoader: StubAttachmentDataLoader(dataByAssetID: [attachment.assetID: Self.sampleData])
        )

        let payload = try loader.loadPayload(for: attachment)

        XCTAssertEqual(payload.attachment, attachment)
        XCTAssertEqual(payload.filename, "sample.png")
        XCTAssertEqual(payload.contentType, "application/octet-stream")
        XCTAssertEqual(payload.base64EncodedData, Self.sampleBase64)
        XCTAssertEqual(payload.dataURL, "data:application/octet-stream;base64,\(Self.sampleBase64)")
    }

    func testPayloadLoaderRejectsEmptyData() {
        let attachment = Self.attachment()
        let loader = LLMsProviderAttachmentPayloadLoader(
            dataLoader: StubAttachmentDataLoader(dataByAssetID: [attachment.assetID: Data()])
        )

        XCTAssertThrowsError(try loader.loadPayload(for: attachment)) { error in
            XCTAssertEqual(error.localizedDescription, "Unable to load attachment data for sample.png.")
        }
    }

    func testPayloadLoaderMapsLoadFailureToMissingData() {
        let attachment = Self.attachment()
        let loader = LLMsProviderAttachmentPayloadLoader(
            dataLoader: StubAttachmentDataLoader(error: StubAttachmentDataError.missing)
        )

        XCTAssertThrowsError(try loader.loadPayload(for: attachment)) { error in
            XCTAssertEqual(error.localizedDescription, "Unable to load attachment data for sample.png.")
        }
    }

    func testOpenAIRendererUsesInjectedAttachmentPayloadLoader() throws {
        let attachment = Self.attachment()
        let messages = try OpenAIChatPromptRenderer.messages(
            for: Self.request(attachment: attachment),
            attachmentPayloadLoader: Self.loader(for: attachment)
        )

        XCTAssertEqual(
            messages.first?.content,
            .parts([
                .text("Describe this."),
                .imageURL(url: Self.sampleDataURL)
            ])
        )
    }

    func testOpenRouterRendererUsesInjectedAttachmentPayloadLoaderForFiles() throws {
        let attachment = Self.attachment(
            kind: .file,
            filename: "notes.pdf",
            contentType: "application/pdf",
            relativePath: "notes.pdf"
        )
        let messages = try OpenRouterChatPromptRenderer.messages(
            for: Self.request(attachment: attachment),
            supportsFileAttachments: true,
            attachmentPayloadLoader: Self.loader(for: attachment)
        )

        XCTAssertEqual(
            messages.first?.content,
            .parts([
                .text("Describe this."),
                .file(filename: "notes.pdf", fileData: "data:application/pdf;base64,\(Self.sampleBase64)")
            ])
        )
    }

    func testAnthropicRendererUsesInjectedAttachmentPayloadLoader() throws {
        let attachment = Self.attachment()
        let renderedPrompt = try AnthropicChatPromptRenderer.render(
            request: Self.request(attachment: attachment),
            attachmentPayloadLoader: Self.loader(for: attachment)
        )

        XCTAssertEqual(
            renderedPrompt.messages.first?.content,
            [
                .imageBase64(mediaType: "image/png", data: Self.sampleBase64),
                .text("Describe this.")
            ]
        )
    }

    func testGeminiRendererUsesInjectedAttachmentPayloadLoader() throws {
        let attachment = Self.attachment()
        let renderedPrompt = try GeminiChatPromptRenderer.render(
            request: Self.request(attachment: attachment),
            attachmentPayloadLoader: Self.loader(for: attachment)
        )

        XCTAssertEqual(
            renderedPrompt.contents.first?.parts,
            [
                .text("Describe this."),
                .inlineData(mimeType: "image/png", data: Self.sampleBase64)
            ]
        )
    }

    func testPollinationsRendererUsesInjectedAttachmentPayloadLoader() throws {
        let attachment = Self.attachment()
        let messages = try PollinationsChatPromptRenderer.messages(
            for: Self.request(attachment: attachment),
            attachmentPayloadLoader: Self.loader(for: attachment)
        )

        XCTAssertEqual(
            messages.first?.content,
            .parts([
                .text("Describe this."),
                .imageURL(url: Self.sampleDataURL)
            ])
        )
    }

    private static let sampleData = Data([0x01, 0x02, 0x03])
    private static let sampleBase64 = "AQID"
    private static let sampleDataURL = "data:image/png;base64,\(sampleBase64)"

    private static func attachment(
        kind: ChatAttachment.Kind = .image,
        filename: String = "sample.png",
        contentType: String = "image/png",
        relativePath: String = "sample.png"
    ) -> ChatAttachment {
        ChatAttachment(
            kind: kind,
            filename: filename,
            contentType: contentType,
            relativePath: relativePath
        )
    }

    private static func request(attachment: ChatAttachment) -> ChatRequest {
        ChatRequest(
            modelID: "test-model",
            messages: [
                makeTestChatMessage(
                    role: .user,
                    content: "Describe this.",
                    attachments: [attachment]
                )
            ],
            context: ChatContext()
        )
    }

    private static func loader(for attachment: ChatAttachment) -> LLMsProviderAttachmentPayloadLoader {
        LLMsProviderAttachmentPayloadLoader(
            dataLoader: StubAttachmentDataLoader(dataByAssetID: [attachment.assetID: sampleData])
        )
    }
}

private final class StubAttachmentDataLoader: LLMsProviderAttachmentDataLoading {
    private let dataByAssetID: [UUID: Data]
    private let error: Error?

    init(dataByAssetID: [UUID: Data] = [:], error: Error? = nil) {
        self.dataByAssetID = dataByAssetID
        self.error = error
    }

    func loadData(for attachment: ChatAttachment) throws -> Data {
        if let error {
            throw error
        }
        guard let data = dataByAssetID[attachment.assetID] else {
            throw StubAttachmentDataError.missing
        }
        return data
    }
}

private enum StubAttachmentDataError: Error {
    case missing
}
