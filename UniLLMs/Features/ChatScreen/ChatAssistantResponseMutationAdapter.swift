//
//  ChatAssistantResponseMutationAdapter.swift
//  UniLLMs
//
//  Applies assistant response view mutations and invalidates chat layout.
//

import Foundation

@MainActor
struct ChatAssistantResponseMutationAdapter<ResponseView> {
    private let invalidateLayout: () -> Void

    init(invalidateLayout: @escaping () -> Void) {
        self.invalidateLayout = invalidateLayout
    }

    func apply(
        to responseView: ResponseView,
        update: (ResponseView) -> Void
    ) {
        update(responseView)
        invalidateLayout()
    }
}

extension ChatAssistantResponseMutationAdapter where ResponseView == AssistantResponseTextView {
    func appendDisplayParts(
        _ displayParts: [ChatResponseDisplayPart],
        to responseView: AssistantResponseTextView
    ) {
        apply(to: responseView) { responseView in
            for part in displayParts {
                responseView.appendDisplayPart(part)
            }
        }
    }

    func showLoadingIfNeeded(in responseView: AssistantResponseTextView) {
        apply(to: responseView) { responseView in
            responseView.showLoadingIfNeeded()
        }
    }

    func setError(
        _ message: String,
        in responseView: AssistantResponseTextView
    ) {
        apply(to: responseView) { responseView in
            responseView.setError(message)
        }
    }

    func finishStreamingContent(in responseView: AssistantResponseTextView) {
        apply(to: responseView) { responseView in
            responseView.finishStreamingContent()
            responseView.setLoadingVisible(false)
        }
    }
}
