//
//  ChatMarkdownRenderedBlock.swift
//  UniLLMs
//
//  Rendered Markdown block values consumed by chat presentation views.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

struct ChatMarkdownImageBlock: Equatable {
    let source: String
    let altText: String
}

enum ChatMarkdownRenderedBlock {
    case text(NSAttributedString)
    case table(ChatMarkdownTableData)
    case image(ChatMarkdownImageBlock)
}
