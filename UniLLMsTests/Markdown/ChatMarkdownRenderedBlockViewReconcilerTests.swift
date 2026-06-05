//
//  ChatMarkdownRenderedBlockViewReconcilerTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class ChatMarkdownRenderedBlockViewReconcilerTests: XCTestCase {
    func testReconcileAllowsCurrentTextIdentityChangeWithoutReplacingView() {
        let stackView = UIStackView()
        let originalText = NSAttributedString(string: "**bo")
        let completedText = NSAttributedString(string: "bold")
        let configuration = ChatMarkdownRenderedBlockViewConfiguration(
            style: .assistant,
            traitCollection: UITraitCollection()
        )

        let records = ChatMarkdownRenderedBlockViewReconciler.append(
            [.text(originalText)],
            to: stackView,
            configuration: configuration
        )
        let originalView = records[0].view

        let nextRecords = ChatMarkdownRenderedBlockViewReconciler.reconcile(
            [.text(completedText)],
            records: records,
            in: stackView,
            allowsIdentityChange: true,
            configuration: configuration
        )

        XCTAssertIdentical(nextRecords[0].view, originalView)
        XCTAssertEqual((nextRecords[0].view as? ChatMarkdownTextView)?.attributedText.string, "bold")
        XCTAssertEqual(stackView.arrangedSubviews.count, 1)
        XCTAssertIdentical(stackView.arrangedSubviews.first, originalView)
    }

    func testUpdateAllInPlaceRequiresExplicitIdentityChangePermission() {
        let originalText = NSAttributedString(string: "**bo")
        let completedText = NSAttributedString(string: "bold")
        let textView = ChatMarkdownTextView(attributedText: originalText)
        let record = ChatMarkdownRenderedBlockViewRecord(
            view: textView,
            kind: .text,
            identity: ChatMarkdownRenderedBlockViewIdentity(.text(originalText))
        )

        XCTAssertFalse(
            ChatMarkdownRenderedBlockViewReconciler.updateAllInPlaceIfPossible(
                [record],
                with: [.text(completedText)]
            )
        )
        XCTAssertEqual(textView.attributedText.string, "**bo")

        XCTAssertTrue(
            ChatMarkdownRenderedBlockViewReconciler.updateAllInPlaceIfPossible(
                [record],
                with: [.text(completedText)],
                allowsIdentityChange: true
            )
        )
        XCTAssertEqual(textView.attributedText.string, "bold")
    }

    func testAppendImageBlockUsesConfiguredImageLoader() {
        let stackView = UIStackView()
        let imageLoader = RecordingMarkdownImageLoader()
        let configuration = ChatMarkdownRenderedBlockViewConfiguration(
            style: .assistant,
            traitCollection: UITraitCollection(),
            imageLoader: imageLoader
        )

        _ = ChatMarkdownRenderedBlockViewReconciler.append(
            [
                imageBlock(source: "https://example.com/top.png")
            ],
            to: stackView,
            configuration: configuration
        )

        XCTAssertEqual(imageLoader.loadedSources, ["https://example.com/top.png"])
    }

    func testAppendNestedImageBlockUsesConfiguredImageLoader() {
        let stackView = UIStackView()
        let imageLoader = RecordingMarkdownImageLoader()
        let configuration = ChatMarkdownRenderedBlockViewConfiguration(
            style: .assistant,
            traitCollection: UITraitCollection(),
            imageLoader: imageLoader
        )

        _ = ChatMarkdownRenderedBlockViewReconciler.append(
            [
                .blockQuote(
                    ChatMarkdownBlockQuoteBlock(
                        children: [
                            imageBlock(source: "https://example.com/nested.png")
                        ]
                    )
                )
            ],
            to: stackView,
            configuration: configuration
        )

        XCTAssertEqual(imageLoader.loadedSources, ["https://example.com/nested.png"])
    }

    private func imageBlock(source: String) -> ChatMarkdownRenderedBlock {
        .image(
            ChatMarkdownImageBlock(
                source: source,
                altText: "Diagram"
            )
        )
    }
}

private final class RecordingMarkdownImageLoader: ChatMarkdownImageLoading {
    private(set) var loadedSources: [String] = []

    @discardableResult
    func loadImage(
        source: String,
        completion _: @escaping @MainActor (UIImage?) -> Void
    ) -> (any ChatMarkdownImageLoadTask)? {
        loadedSources.append(source)
        return nil
    }
}
