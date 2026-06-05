//
//  ChatMessageStackAdapter.swift
//  UniLLMs
//
//  Owns chat message stack mutations and the layout constraints for inserted message views.
//

import UIKit

@MainActor
final class ChatMessageStackAdapter {
    typealias AttachmentDisplayBuilder = @MainActor ([ChatAttachment]) -> [ChatAttachmentPreviewDisplay]

    struct OutgoingMessageViews {
        var bubbleView: SentMessageBubbleView
        var responseView: AssistantResponseTextView
    }

    private weak var stackView: UIStackView?
    private let maximumBubbleWidthRatio: CGFloat
    private let attachmentDisplayBuilder: AttachmentDisplayBuilder
    private let configureSentMessage: (SentMessageBubbleView, UUID) -> Void

    init(
        stackView: UIStackView,
        maximumBubbleWidthRatio: CGFloat,
        attachmentDisplayBuilder: @escaping AttachmentDisplayBuilder = {
            ChatAttachmentPreviewDisplay.placeholders(for: $0)
        },
        configureSentMessage: @escaping (SentMessageBubbleView, UUID) -> Void
    ) {
        self.stackView = stackView
        self.maximumBubbleWidthRatio = maximumBubbleWidthRatio
        self.attachmentDisplayBuilder = attachmentDisplayBuilder
        self.configureSentMessage = configureSentMessage
    }

    var isEmpty: Bool {
        stackView?.arrangedSubviews.isEmpty ?? true
    }

    func containsSentMessage(withID messageID: UUID) -> Bool {
        sentMessageBubble(withID: messageID) != nil
    }

    func arrangedSubviewIndexOfSentMessage(withID messageID: UUID) -> Int? {
        stackView?.arrangedSubviews.firstIndex { view in
            isSentMessageBubble(view, withID: messageID)
        }
    }

    @discardableResult
    func updateAttachmentDisplays(
        forMessageID messageID: UUID,
        displays: [ChatAttachmentPreviewDisplay]
    ) -> Bool {
        guard let bubbleView = sentMessageBubble(withID: messageID) else {
            return false
        }

        bubbleView.updateAttachmentDisplays(displays)
        return true
    }

    @discardableResult
    func appendStoredUserMessage(
        id: UUID,
        text: String,
        attachments: [ChatAttachment]
    ) -> SentMessageBubbleView {
        let bubbleView = makeSentMessageBubbleView(
            messageID: id,
            text: text,
            attachments: attachments,
            initialAlpha: 1.0
        )
        appendBubbleView(bubbleView)
        return bubbleView
    }

    func appendOutgoingMessage(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment],
        initialBubbleAlpha: CGFloat = 1.0
    ) -> OutgoingMessageViews {
        let bubbleView = makeSentMessageBubbleView(
            messageID: messageID,
            text: text,
            attachments: attachments,
            initialAlpha: initialBubbleAlpha
        )
        let responseView = makeAssistantResponseView(initiallyHidden: true)
        appendBubbleView(bubbleView)
        appendResponseView(responseView)
        return OutgoingMessageViews(
            bubbleView: bubbleView,
            responseView: responseView
        )
    }

    @discardableResult
    func appendAssistantResponseView() -> AssistantResponseTextView {
        let responseView = makeAssistantResponseView(initiallyHidden: false)
        appendResponseView(responseView)
        return responseView
    }

    func removeMessagesStarting(at firstRemovedIndex: Int) {
        guard let stackView,
              stackView.arrangedSubviews.indices.contains(firstRemovedIndex) else {
            return
        }

        removeViews(Array(stackView.arrangedSubviews[firstRemovedIndex...]))
    }

    @discardableResult
    func removeAll() -> Bool {
        guard let stackView,
              !stackView.arrangedSubviews.isEmpty else {
            return false
        }

        removeViews(stackView.arrangedSubviews)
        return true
    }

    func removeViews(_ views: [UIView]) {
        guard let stackView else {
            return
        }

        for view in views {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func sentMessageBubble(withID messageID: UUID) -> SentMessageBubbleView? {
        stackView?.arrangedSubviews.compactMap { $0 as? SentMessageBubbleView }
            .first { $0.messageID == messageID }
    }

    private func isSentMessageBubble(_ view: UIView, withID messageID: UUID) -> Bool {
        (view as? SentMessageBubbleView)?.messageID == messageID
    }

    private func makeSentMessageBubbleView(
        messageID: UUID,
        text: String,
        attachments: [ChatAttachment],
        initialAlpha: CGFloat
    ) -> SentMessageBubbleView {
        let bubbleView = SentMessageBubbleView(
            messageID: messageID,
            text: text,
            attachments: attachments,
            attachmentDisplays: attachmentDisplayBuilder(attachments)
        )
        configureSentMessage(bubbleView, messageID)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.alpha = initialAlpha
        bubbleView.setContentHuggingPriority(.required, for: .vertical)
        bubbleView.setContentCompressionResistancePriority(.required, for: .vertical)
        return bubbleView
    }

    private func makeAssistantResponseView(initiallyHidden: Bool) -> AssistantResponseTextView {
        let responseView = AssistantResponseTextView()
        responseView.translatesAutoresizingMaskIntoConstraints = false
        responseView.isHidden = initiallyHidden
        responseView.setContentHuggingPriority(.required, for: .vertical)
        responseView.setContentCompressionResistancePriority(.required, for: .vertical)
        return responseView
    }

    private func appendBubbleView(_ bubbleView: SentMessageBubbleView) {
        guard let stackView else {
            return
        }

        stackView.addArrangedSubview(bubbleView)
        bubbleView.widthAnchor.constraint(
            lessThanOrEqualTo: stackView.widthAnchor,
            multiplier: maximumBubbleWidthRatio
        ).isActive = true
    }

    private func appendResponseView(_ responseView: AssistantResponseTextView) {
        guard let stackView else {
            return
        }

        stackView.addArrangedSubview(responseView)
        responseView.widthAnchor.constraint(
            equalTo: stackView.widthAnchor
        ).isActive = true
    }
}
