//
//  SentMessageBubbleActionMenuPolicy.swift
//  UniLLMs
//
//  Describes sent-message context menu actions without tying decisions to UIKit.
//

import Foundation

enum SentMessageBubbleAction: Equatable {
    case copy
    case resend
    case editAndResend
    case showHistory
}

struct SentMessageBubbleActionMenuItem: Equatable {
    var action: SentMessageBubbleAction
    var title: String
    var systemImageName: String
}

enum SentMessageBubbleActionMenuPolicy {
    static func makeItems(editHistoryCount: Int) -> [SentMessageBubbleActionMenuItem] {
        var items = [
            SentMessageBubbleActionMenuItem(
                action: .copy,
                title: String(localized: .chatCopy),
                systemImageName: "doc.on.doc"
            ),
            SentMessageBubbleActionMenuItem(
                action: .resend,
                title: String(localized: .chatResend),
                systemImageName: "arrow.clockwise"
            ),
            SentMessageBubbleActionMenuItem(
                action: .editAndResend,
                title: String(localized: .chatEditAndResend),
                systemImageName: "square.and.pencil"
            )
        ]

        if editHistoryCount > 0 {
            items.append(
                SentMessageBubbleActionMenuItem(
                    action: .showHistory,
                    title: historyTitle(editHistoryCount: editHistoryCount),
                    systemImageName: "clock"
                )
            )
        }

        return items
    }

    private static func historyTitle(editHistoryCount: Int) -> String {
        editHistoryCount == 1
            ? String(localized: .generalHistory)
            : String(localized: .chatHistoryCountFormat(editHistoryCount))
    }
}
