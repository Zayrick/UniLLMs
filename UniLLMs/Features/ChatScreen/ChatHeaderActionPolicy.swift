//
//  ChatHeaderActionPolicy.swift
//  UniLLMs
//
//  Decides the right header action behavior from chat screen state.
//  Created by Codex on 2026/6/5.
//

import Foundation

struct ChatHeaderActionPolicy: Equatable {
    enum Action: Equatable {
        case startNewConversation
        case togglePrivacyMode
        case ignore
    }

    static func action(
        isResponseActive: Bool,
        hasChatContent: Bool
    ) -> Action {
        guard !isResponseActive else {
            return .ignore
        }

        return hasChatContent ? .startNewConversation : .togglePrivacyMode
    }

}
