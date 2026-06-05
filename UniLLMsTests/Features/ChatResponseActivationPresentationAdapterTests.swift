//
//  ChatResponseActivationPresentationAdapterTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

@MainActor
final class ChatResponseActivationPresentationAdapterTests: XCTestCase {
    func testActivePresentationDisablesComposerAndStartsStreamingChrome() {
        XCTAssertEqual(
            ChatResponseActivationPresentation.active,
            ChatResponseActivationPresentation(
                isComposerSendingEnabled: false,
                isStreamingResponseActive: true,
                isBackgroundFlowing: true
            )
        )
    }

    func testInactivePresentationEnablesComposerAndStopsStreamingChrome() {
        XCTAssertEqual(
            ChatResponseActivationPresentation.inactive,
            ChatResponseActivationPresentation(
                isComposerSendingEnabled: true,
                isStreamingResponseActive: false,
                isBackgroundFlowing: false
            )
        )
    }

    func testPrepareActivationAppliesChromeWithoutRefreshingHeader() {
        let recorder = EventRecorder()
        let adapter = makeAdapter(recorder: recorder)

        adapter.prepareActivation(animated: true)

        XCTAssertEqual(
            recorder.events,
            [
                .composerSendingEnabled(false),
                .composerStreamingActive(isActive: true, animated: true),
                .backgroundFlowing(isFlowing: true, animated: true)
            ]
        )
    }

    func testCompleteActivationRefreshesHeaderAfterStreamBecomesActive() {
        let recorder = EventRecorder()
        let adapter = makeAdapter(recorder: recorder)

        adapter.completeActivation(animated: true)

        XCTAssertEqual(recorder.events, [.header(animated: true)])
    }

    func testDeactivateRestoresChromeBeforeRefreshingHeader() {
        let recorder = EventRecorder()
        let adapter = makeAdapter(recorder: recorder)

        adapter.deactivate(animated: false)

        XCTAssertEqual(
            recorder.events,
            [
                .composerSendingEnabled(true),
                .composerStreamingActive(isActive: false, animated: false),
                .backgroundFlowing(isFlowing: false, animated: false),
                .header(animated: false)
            ]
        )
    }

    private func makeAdapter(recorder: EventRecorder) -> ChatResponseActivationPresentationAdapter {
        ChatResponseActivationPresentationAdapter(
            setComposerSendingEnabled: { recorder.events.append(.composerSendingEnabled($0)) },
            setComposerStreamingActive: { isActive, animated in
                recorder.events.append(.composerStreamingActive(isActive: isActive, animated: animated))
            },
            setBackgroundFlowing: { isFlowing, animated in
                recorder.events.append(.backgroundFlowing(isFlowing: isFlowing, animated: animated))
            },
            updateHeader: { recorder.events.append(.header(animated: $0)) }
        )
    }
}

private final class EventRecorder {
    var events: [Event] = []
}

private enum Event: Equatable {
    case composerSendingEnabled(Bool)
    case composerStreamingActive(isActive: Bool, animated: Bool)
    case backgroundFlowing(isFlowing: Bool, animated: Bool)
    case header(animated: Bool)
}
