//
//  LLMsProviderAttachmentPayload.swift
//  UniLLMs
//
//  Loads chat attachments into provider-ready payload bytes without exposing
//  the underlying attachment store to provider renderers.
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated protocol LLMsProviderAttachmentDataLoading {
    func loadData(for attachment: ChatAttachment) throws -> Data
}

nonisolated struct LLMsProviderAttachmentPayload: Equatable {
    static let fallbackContentType = "application/octet-stream"

    var attachment: ChatAttachment
    var data: Data

    var filename: String {
        attachment.filename
    }

    var contentType: String {
        attachment.contentType.isEmpty
            ? Self.fallbackContentType
            : attachment.contentType
    }

    var base64EncodedData: String {
        data.base64EncodedString()
    }

    var dataURL: String {
        "data:\(contentType);base64,\(base64EncodedData)"
    }
}

nonisolated enum LLMsProviderAttachmentPayloadError: LocalizedError, Equatable {
    case missingAttachmentData(String)

    var errorDescription: String? {
        switch self {
        case let .missingAttachmentData(filename):
            return String(localized: .providersErrorMissingAttachmentDataFormat(filename))
        }
    }
}

nonisolated struct LLMsProviderAttachmentPayloadLoader {
    static let shared = LLMsProviderAttachmentPayloadLoader()

    private let dataLoader: any LLMsProviderAttachmentDataLoading

    init(dataLoader: any LLMsProviderAttachmentDataLoading = ChatAttachmentStore.shared) {
        self.dataLoader = dataLoader
    }

    func loadPayload(for attachment: ChatAttachment) throws -> LLMsProviderAttachmentPayload {
        let data: Data
        do {
            data = try dataLoader.loadData(for: attachment)
        } catch {
            throw LLMsProviderAttachmentPayloadError.missingAttachmentData(attachment.filename)
        }

        guard !data.isEmpty else {
            throw LLMsProviderAttachmentPayloadError.missingAttachmentData(attachment.filename)
        }

        return LLMsProviderAttachmentPayload(attachment: attachment, data: data)
    }
}

nonisolated extension ChatAttachmentStore: LLMsProviderAttachmentDataLoading {}
