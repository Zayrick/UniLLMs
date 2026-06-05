//
//  ChatMessageRevisionHistoryItem.swift
//  UniLLMs
//
//  Prepares message revision history rows without tying the rules to UIKit.
//

import Foundation

struct ChatMessageRevisionHistoryItem: Equatable, Identifiable {
    var revision: ChatMessageRevision
    var title: String
    var subtitle: String
    var followUpUserMessageCount: Int

    var id: UUID {
        revision.id
    }

    init(
        revision: ChatMessageRevision,
        dateFormatter: DateFormatter = Self.defaultDateFormatter,
        attachmentFallbackTitle: String = String(localized: .chatAttachment)
    ) {
        self.revision = revision
        title = Self.title(
            for: revision,
            attachmentFallbackTitle: attachmentFallbackTitle
        )
        subtitle = dateFormatter.string(from: revision.archivedAt)
        followUpUserMessageCount = Self.followUpUserMessageCount(in: revision)
    }

    static func items(
        from revisions: [ChatMessageRevision],
        dateFormatter: DateFormatter = defaultDateFormatter,
        attachmentFallbackTitle: String = String(localized: .chatAttachment)
    ) -> [ChatMessageRevisionHistoryItem] {
        revisions.map {
            ChatMessageRevisionHistoryItem(
                revision: $0,
                dateFormatter: dateFormatter,
                attachmentFallbackTitle: attachmentFallbackTitle
            )
        }
    }

    private static func title(
        for revision: ChatMessageRevision,
        attachmentFallbackTitle: String
    ) -> String {
        let title = userMessageText(in: revision).singleLineRevisionHistoryTitle
        guard title.isEmpty else {
            return title
        }

        return firstAttachmentTitle(in: revision) ?? attachmentFallbackTitle
    }

    private static func userMessageText(in revision: ChatMessageRevision) -> String {
        for event in revision.events {
            switch event.kind {
            case let .userMessage(text),
                 let .userMessageWithAttachments(text, _):
                return text
            case .assistantReasoning,
                 .assistantContent,
                 .assistantToolCalls,
                 .toolEvent:
                continue
            }
        }
        return ""
    }

    private static func firstAttachmentTitle(in revision: ChatMessageRevision) -> String? {
        for event in revision.events {
            guard case let .userMessageWithAttachments(_, attachments) = event.kind else {
                continue
            }

            let filename = attachments.first?.filename
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return filename.isEmpty ? nil : filename
        }

        return nil
    }

    private static func followUpUserMessageCount(in revision: ChatMessageRevision) -> Int {
        var hasSeenAnchorMessage = false
        var count = 0
        for event in revision.events {
            switch event.kind {
            case .userMessage,
                 .userMessageWithAttachments:
                if hasSeenAnchorMessage {
                    count += 1
                } else {
                    hasSeenAnchorMessage = true
                }
            case .assistantReasoning,
                 .assistantContent,
                 .assistantToolCalls,
                 .toolEvent:
                continue
            }
        }
        return count
    }

    private static let defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension String {
    var singleLineRevisionHistoryTitle: String {
        components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
