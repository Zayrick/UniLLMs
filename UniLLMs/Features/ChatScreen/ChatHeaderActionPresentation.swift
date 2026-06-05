//
//  ChatHeaderActionPresentation.swift
//  UniLLMs
//
//  Describes the right header action without tying its state rules to UIKit.
//

import Foundation

struct ChatHeaderActionPresentation: Equatable {
    enum AccessibilityText: Equatable {
        case generatingResponse
        case newChat
        case privateChat
        case privateChatActive
        case privateChatHint
        case privateChatActiveHint
    }

    var iconSystemName: String?
    var showsActivityIndicator: Bool
    var usesAccentColor: Bool
    var isSelected: Bool
    var accessibilityLabel: AccessibilityText
    var accessibilityHint: AccessibilityText?

    static func make(
        isGeneratingResponse: Bool,
        isPrivateModeEnabled: Bool,
        hasChatContent: Bool
    ) -> ChatHeaderActionPresentation {
        if isGeneratingResponse {
            return ChatHeaderActionPresentation(
                iconSystemName: nil,
                showsActivityIndicator: true,
                usesAccentColor: false,
                isSelected: isPrivateModeEnabled && !hasChatContent,
                accessibilityLabel: .generatingResponse,
                accessibilityHint: nil
            )
        }

        if hasChatContent {
            return ChatHeaderActionPresentation(
                iconSystemName: "plus.message",
                showsActivityIndicator: false,
                usesAccentColor: false,
                isSelected: false,
                accessibilityLabel: .newChat,
                accessibilityHint: nil
            )
        }

        if isPrivateModeEnabled {
            return ChatHeaderActionPresentation(
                iconSystemName: "lock.app.dashed",
                showsActivityIndicator: false,
                usesAccentColor: true,
                isSelected: true,
                accessibilityLabel: .privateChatActive,
                accessibilityHint: .privateChatActiveHint
            )
        }

        return ChatHeaderActionPresentation(
            iconSystemName: "app.dashed",
            showsActivityIndicator: false,
            usesAccentColor: false,
            isSelected: false,
            accessibilityLabel: .privateChat,
            accessibilityHint: .privateChatHint
        )
    }
}

extension ChatHeaderActionPresentation.AccessibilityText {
    var localizedString: String {
        switch self {
        case .generatingResponse:
            return String(localized: .chatGeneratingResponse)
        case .newChat:
            return String(localized: .chatNewChat)
        case .privateChat:
            return String(localized: .chatPrivateChat)
        case .privateChatActive:
            return String(localized: .chatPrivateChatActive)
        case .privateChatHint:
            return String(localized: .chatPrivateChatHint)
        case .privateChatActiveHint:
            return String(localized: .chatPrivateChatActiveHint)
        }
    }
}
