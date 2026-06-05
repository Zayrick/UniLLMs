//
//  ChatPendingAttachmentDisplay.swift
//  UniLLMs
//
//  Feature-level display data for pending composer attachments.
//

import UIKit

struct ChatPendingAttachmentDisplay: Equatable {
    var id: UUID
    var image: UIImage?
    var filename: String
    var isFile: Bool
}
