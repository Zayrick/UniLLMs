//
//  ChatOutgoingMessageTransactionWorkflowTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatOutgoingMessageTransactionWorkflowTests: XCTestCase {
    func testNewMessageTransactionActivatesResponseBeforeLoadingAfterSendAnimation() {
        let messageID = UUID()
        let attachment = makeAttachment(filename: "photo.jpg")
        let plan = ChatOutgoingMessageTransactionPlan.newMessage(
            text: "Hello",
            attachments: [attachment],
            messageID: messageID
        )
        let environment = makeEnvironment()

        environment.workflow.perform(
            plan,
            preparedStream: makePreparedStream(),
            existingMessagesSnapshot: .empty,
            sendTransition: ChatComposerSendTransition(
                text: "Hello",
                backgroundGlobalFrame: .zero
            )
        )

        XCTAssertEqual(environment.events.values, [
            "append:Hello:0.0",
            "loadAttachments:photo.jpg",
            "layout",
            "scroll",
            "layout",
            "activate",
            "animateExistingMessages",
            "presentAssistantLoading"
        ])
        XCTAssertEqual(environment.screen.animatedAttachments, [attachment])
    }

    func testReplacementTransactionRemovesOldMessagesAndShowsLoadingImmediately() {
        let messageID = UUID()
        let attachment = makeAttachment(filename: "notes.txt")
        let resendPlan = ChatMessageResendPlan(
            messageID: messageID,
            text: "Edited",
            attachments: [attachment],
            firstRemovedIndex: 3,
            presentationState: .replacementMessage(
                prompt: "Edited",
                attachments: [attachment]
            )
        )
        let plan = ChatOutgoingMessageTransactionPlan.replacement(resendPlan: resendPlan)
        let environment = makeEnvironment()

        environment.workflow.perform(
            plan,
            preparedStream: makePreparedStream(),
            existingMessagesSnapshot: .empty,
            sendTransition: nil
        )

        XCTAssertEqual(environment.events.values, [
            "removeReplacementMessages:3",
            "append:Edited:1.0",
            "loadAttachments:notes.txt",
            "layout",
            "scroll",
            "layout",
            "activate",
            "refreshEditHistory",
            "animateExistingMessages",
            "presentAssistantLoading"
        ])
    }

    func testEditHistoryRefreshUsesTransactionPlanMessageID() {
        let planMessageID = UUID()
        let outgoingViewMessageID = UUID()
        let resendPlan = ChatMessageResendPlan(
            messageID: planMessageID,
            text: "Edited",
            attachments: [],
            firstRemovedIndex: 1,
            presentationState: .replacementMessage(
                prompt: "Edited",
                attachments: []
            )
        )
        let environment = makeEnvironment(outgoingViewMessageID: outgoingViewMessageID)

        environment.workflow.perform(
            .replacement(resendPlan: resendPlan),
            preparedStream: makePreparedStream(),
            existingMessagesSnapshot: .empty,
            sendTransition: nil
        )

        XCTAssertEqual(environment.messages.refreshedMessageIDs, [planMessageID])
        XCTAssertNotEqual(planMessageID, outgoingViewMessageID)
    }

    func testAfterSendAnimationWithoutTransitionShowsLoadingWithoutAnimating() {
        let plan = ChatOutgoingMessageTransactionPlan.newMessage(
            text: "Hello",
            attachments: [],
            messageID: UUID()
        )
        let environment = makeEnvironment()

        environment.workflow.perform(
            plan,
            preparedStream: makePreparedStream(),
            existingMessagesSnapshot: .empty,
            sendTransition: nil
        )

        XCTAssertEqual(environment.events.values.last, "presentAssistantLoading")
    }

    func testResponseActivationUsesTransactionPlanMessageID() {
        let planMessageID = UUID()
        let outgoingViewMessageID = UUID()
        let plan = ChatOutgoingMessageTransactionPlan.newMessage(
            text: "Hello",
            attachments: [],
            messageID: planMessageID
        )
        let environment = makeEnvironment(outgoingViewMessageID: outgoingViewMessageID)

        environment.workflow.perform(
            plan,
            preparedStream: makePreparedStream(),
            existingMessagesSnapshot: .empty,
            sendTransition: nil
        )

        XCTAssertEqual(environment.responseActivator.activatedSentMessageIDs, [planMessageID])
        XCTAssertNotEqual(planMessageID, outgoingViewMessageID)
    }

    func testResponseActivationAdapterBuildsContextWithExplicitSentMessageID() {
        let sentMessageID = UUID()
        let outgoingViewMessageID = UUID()
        var capturedContext: ChatOutgoingMessageTransactionResponseActivationAdapter.ActiveResponseContext?
        let adapter = ChatOutgoingMessageTransactionResponseActivationAdapter { _, _, _, context in
            capturedContext = context
        }
        let outgoingViews = ChatMessageStackAdapter.OutgoingMessageViews(
            bubbleView: SentMessageBubbleView(
                messageID: outgoingViewMessageID,
                text: "Hello",
                attachments: []
            ),
            responseView: AssistantResponseTextView()
        )

        adapter.activateAssistantResponseStream(
            makePreparedStream(),
            sentMessageID: sentMessageID,
            outgoingViews: outgoingViews,
            presentationState: .newMessage(prompt: "Hello", attachments: [])
        )

        XCTAssertEqual(capturedContext?.sentMessageID, sentMessageID)
        XCTAssertNotEqual(sentMessageID, outgoingViewMessageID)
    }

    func testScreenAdapterPresentsLoadingAfterSendAnimation() {
        let environment = makeScreenAdapterEnvironment()
        let attachment = makeAttachment(filename: "photo.jpg")

        environment.adapter.presentAssistantLoading(
            presentation: .afterSendAnimation,
            outgoingViews: makeOutgoingViews(),
            sendTransition: ChatComposerSendTransition(
                text: "Hello",
                backgroundGlobalFrame: .zero
            ),
            attachments: [attachment]
        )

        XCTAssertEqual(environment.events.values, [
            "animateSentMessage",
            "showLoading"
        ])
        XCTAssertEqual(environment.animator.animatedAttachments, [attachment])
    }

    func testScreenAdapterShowsLoadingWithoutAnimationWhenTransitionIsMissing() {
        let environment = makeScreenAdapterEnvironment()

        environment.adapter.presentAssistantLoading(
            presentation: .afterSendAnimation,
            outgoingViews: makeOutgoingViews(),
            sendTransition: nil,
            attachments: []
        )

        XCTAssertEqual(environment.events.values, ["showLoading"])
        XCTAssertTrue(environment.animator.animatedAttachments.isEmpty)
    }

    func testScreenAdapterShowsImmediateLoadingWithoutAnimation() {
        let environment = makeScreenAdapterEnvironment()

        environment.adapter.presentAssistantLoading(
            presentation: .immediately,
            outgoingViews: makeOutgoingViews(),
            sendTransition: ChatComposerSendTransition(
                text: "Hello",
                backgroundGlobalFrame: .zero
            ),
            attachments: []
        )

        XCTAssertEqual(environment.events.values, ["showLoading"])
        XCTAssertTrue(environment.animator.animatedAttachments.isEmpty)
    }

    private func makeEnvironment(outgoingViewMessageID: UUID? = nil) -> TestEnvironment {
        let events = EventLog()
        let messages = RecordingMessageAdapter(
            events: events,
            outgoingViewMessageID: outgoingViewMessageID
        )
        let screen = RecordingScreenAdapter(events: events)
        let responseActivator = RecordingResponseActivator(events: events)
        let workflow = ChatOutgoingMessageTransactionWorkflow(
            messages: messages,
            screen: screen,
            responseActivator: responseActivator
        )
        return TestEnvironment(
            workflow: workflow,
            events: events,
            messages: messages,
            screen: screen,
            responseActivator: responseActivator
        )
    }

    private func makeScreenAdapterEnvironment() -> ScreenAdapterEnvironment {
        let events = EventLog()
        let animator = RecordingSentMessageSendAnimator(events: events)
        let adapter = ChatOutgoingMessageTransactionScreenAdapter(
            layoutView: UIView(),
            existingMessagesShiftAnimator: ChatExistingMessagesShiftAnimator(
                hostView: UIView(),
                referenceView: UIView(),
                scrollView: UIScrollView(),
                stackView: UIStackView(),
                visibilityMargin: 0.0,
                animationDuration: 0.0,
                dampingRatio: 1.0
            ),
            sentMessageSendAnimator: animator,
            scrollToBottom: { events.append("scroll") },
            presentLoading: { _ in events.append("showLoading") }
        )
        return ScreenAdapterEnvironment(
            adapter: adapter,
            events: events,
            animator: animator
        )
    }

    private func makeOutgoingViews() -> ChatMessageStackAdapter.OutgoingMessageViews {
        ChatMessageStackAdapter.OutgoingMessageViews(
            bubbleView: SentMessageBubbleView(text: "Hello"),
            responseView: AssistantResponseTextView()
        )
    }

    private func makePreparedStream() -> ChatPreparedAssistantResponseStream {
        ChatPreparedAssistantResponseStream(
            responseStream: AsyncThrowingStream { continuation in
                continuation.finish()
            },
            continuationTask: nil
        )
    }

    private func makeAttachment(filename: String) -> ChatAttachment {
        ChatAttachment(
            kind: .file,
            filename: filename,
            contentType: "text/plain",
            relativePath: filename
        )
    }

    private struct TestEnvironment {
        let workflow: ChatOutgoingMessageTransactionWorkflow
        let events: EventLog
        let messages: RecordingMessageAdapter
        let screen: RecordingScreenAdapter
        let responseActivator: RecordingResponseActivator
    }

    private struct ScreenAdapterEnvironment {
        let adapter: ChatOutgoingMessageTransactionScreenAdapter
        let events: EventLog
        let animator: RecordingSentMessageSendAnimator
    }
}

@MainActor
private final class EventLog {
    private(set) var values: [String] = []

    func append(_ event: String) {
        values.append(event)
    }
}

@MainActor
private final class RecordingMessageAdapter: ChatOutgoingMessageTransactionMessageAdapting {
    private let events: EventLog
    private let outgoingViewMessageID: UUID?
    private(set) var refreshedMessageIDs: [UUID] = []

    init(events: EventLog, outgoingViewMessageID: UUID?) {
        self.events = events
        self.outgoingViewMessageID = outgoingViewMessageID
    }

    func removeReplacementMessages(startingAt firstRemovedIndex: Int) {
        events.append("removeReplacementMessages:\(firstRemovedIndex)")
    }

    func appendOutgoingMessage(
        for transactionPlan: ChatOutgoingMessageTransactionPlan
    ) -> ChatMessageStackAdapter.OutgoingMessageViews {
        events.append("append:\(transactionPlan.prompt):\(transactionPlan.initialBubbleAlpha)")
        return ChatMessageStackAdapter.OutgoingMessageViews(
            bubbleView: SentMessageBubbleView(
                messageID: outgoingViewMessageID ?? transactionPlan.messageID,
                text: transactionPlan.prompt,
                attachments: transactionPlan.attachments
            ),
            responseView: AssistantResponseTextView()
        )
    }

    func loadAttachmentDisplays(for transactionPlan: ChatOutgoingMessageTransactionPlan) {
        let filenames = transactionPlan.attachments.map(\.filename).joined(separator: ",")
        events.append("loadAttachments:\(filenames)")
    }

    func refreshEditHistory(for bubbleView: SentMessageBubbleView, messageID: UUID) {
        events.append("refreshEditHistory")
        refreshedMessageIDs.append(messageID)
    }
}

@MainActor
private final class RecordingScreenAdapter: ChatOutgoingMessageTransactionScreenAdapting {
    private let events: EventLog
    private(set) var animatedAttachments: [ChatAttachment] = []

    init(events: EventLog) {
        self.events = events
    }

    func layoutIfNeeded() {
        events.append("layout")
    }

    func scrollToBottom() {
        events.append("scroll")
    }

    func animateExistingMessages(from snapshot: ChatExistingMessagesShiftAnimator.Snapshot) {
        events.append("animateExistingMessages")
    }

    func presentAssistantLoading(
        presentation: ChatOutgoingMessageTransactionPlan.LoadingPresentation,
        outgoingViews: ChatMessageStackAdapter.OutgoingMessageViews,
        sendTransition: ChatComposerSendTransition?,
        attachments: [ChatAttachment]
    ) {
        events.append("presentAssistantLoading")
        animatedAttachments = attachments
    }
}

@MainActor
private final class RecordingSentMessageSendAnimator: ChatSentMessageSendAnimating {
    private let events: EventLog
    private(set) var animatedAttachments: [ChatAttachment] = []

    init(events: EventLog) {
        self.events = events
    }

    func animate(
        bubbleView: SentMessageBubbleView,
        transition: ChatComposerSendTransition,
        attachments: [ChatAttachment],
        completion: (() -> Void)?
    ) {
        events.append("animateSentMessage")
        animatedAttachments = attachments
        completion?()
    }
}

@MainActor
private final class RecordingResponseActivator: ChatOutgoingMessageTransactionResponseActivating {
    private let events: EventLog
    private(set) var activatedSentMessageIDs: [UUID] = []

    init(events: EventLog) {
        self.events = events
    }

    func activateAssistantResponseStream(
        _ preparedStream: ChatPreparedAssistantResponseStream,
        sentMessageID: UUID,
        outgoingViews: ChatMessageStackAdapter.OutgoingMessageViews,
        presentationState: ChatResponsePresentationState
    ) {
        events.append("activate")
        activatedSentMessageIDs.append(sentMessageID)
    }
}
