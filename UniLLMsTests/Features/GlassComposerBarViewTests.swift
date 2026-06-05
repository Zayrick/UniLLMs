//
//  GlassComposerBarViewTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

@MainActor
final class GlassComposerBarViewTests: XCTestCase {
    func testSetPendingAttachmentsUpdatesExistingImageForSameID() {
        let view = GlassComposerBarView()
        let id = UUID()
        let firstImage = UIImage()
        let secondImage = UIImage()

        view.setPendingAttachments([
            Self.display(id: id, filename: "first.png", image: firstImage)
        ])
        view.setPendingAttachments([
            Self.display(id: id, filename: "second.png", image: secondImage)
        ])

        XCTAssertFalse(Self.imageViews(in: view).contains { $0.image === firstImage })
        XCTAssertTrue(Self.imageViews(in: view).contains { $0.image === secondImage })
        XCTAssertFalse(Self.accessibilityLabels(in: view).contains("first.png"))
        XCTAssertTrue(Self.accessibilityLabels(in: view).contains("second.png"))
    }

    func testSetPendingAttachmentsReordersExistingChipsToMatchInputOrder() throws {
        let view = GlassComposerBarView()
        let firstID = UUID()
        let secondID = UUID()

        view.setPendingAttachments([
            Self.display(id: firstID, filename: "first.png"),
            Self.display(id: secondID, filename: "second.png")
        ])
        view.setPendingAttachments([
            Self.display(id: secondID, filename: "second.png"),
            Self.display(id: firstID, filename: "first.png")
        ])

        let attachmentStack = try XCTUnwrap(
            Self.stackViews(in: view).first { stackView in
                Set(Self.attachmentLabels(in: stackView)) == ["first.png", "second.png"]
            }
        )
        XCTAssertEqual(
            attachmentStack.arrangedSubviews.compactMap(Self.firstAccessibilityLabel),
            ["second.png", "first.png"]
        )
    }

    func testRemoveActionKeepsExistingAttachmentIDAfterDisplayUpdate() throws {
        let view = GlassComposerBarView()
        let id = UUID()
        var removedID: UUID?
        view.onRemoveAttachment = { removedID = $0 }

        view.setPendingAttachments([
            Self.display(id: id, filename: "first.png")
        ])
        view.setPendingAttachments([
            Self.display(id: id, filename: "second.png")
        ])

        let removeButton = try XCTUnwrap(
            Self.buttons(in: view).first {
                $0.accessibilityLabel == String(localized: .composerRemoveAttachment)
            }
        )
        removeButton.sendActions(for: .touchUpInside)

        XCTAssertEqual(removedID, id)
    }

    private static func display(
        id: UUID,
        filename: String,
        image: UIImage? = nil,
        isFile: Bool = false
    ) -> GlassComposerBarView.PendingAttachmentDisplay {
        GlassComposerBarView.PendingAttachmentDisplay(
            id: id,
            image: image,
            filename: filename,
            isFile: isFile
        )
    }

    private static func imageViews(in view: UIView) -> [UIImageView] {
        allSubviews(in: view).compactMap { $0 as? UIImageView }
    }

    private static func buttons(in view: UIView) -> [UIButton] {
        allSubviews(in: view).compactMap { $0 as? UIButton }
    }

    private static func stackViews(in view: UIView) -> [UIStackView] {
        allSubviews(in: view).compactMap { $0 as? UIStackView }
    }

    private static func attachmentLabels(in stackView: UIStackView) -> [String] {
        stackView.arrangedSubviews.compactMap(firstAccessibilityLabel)
    }

    private static func firstAccessibilityLabel(in view: UIView) -> String? {
        if let label = view.accessibilityLabel {
            return label
        }

        return allSubviews(in: view).first { $0.accessibilityLabel != nil }?.accessibilityLabel
    }

    private static func accessibilityLabels(in view: UIView) -> [String] {
        allSubviews(in: view).compactMap(\.accessibilityLabel)
    }

    private static func allSubviews(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }
}
