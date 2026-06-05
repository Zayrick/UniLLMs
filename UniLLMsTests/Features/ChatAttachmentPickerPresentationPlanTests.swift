//
//  ChatAttachmentPickerPresentationPlanTests.swift
//  UniLLMsTests
//

import PhotosUI
import UniformTypeIdentifiers
import XCTest
@testable import UniLLMs

@MainActor
final class ChatAttachmentPickerPresentationPlanTests: XCTestCase {
    func testCameraSourceReturnsCameraPickerWhenAvailable() {
        let plan = ChatAttachmentPickerPresentationPlan.make(
            source: .camera,
            isCameraAvailable: { true }
        )

        guard case .cameraPicker = plan else {
            return XCTFail("Expected camera picker.")
        }
    }

    func testCameraSourceReturnsErrorWhenUnavailable() {
        let plan = ChatAttachmentPickerPresentationPlan.make(
            source: .camera,
            isCameraAvailable: { false }
        )

        XCTAssertEqual(plan.errorMessage, String(localized: .chatAttachmentCameraUnavailable))
    }

    func testPhotoLibrarySourceBuildsImageOnlyCurrentRepresentationConfiguration() {
        var cameraAvailabilityCalls = 0

        let plan = ChatAttachmentPickerPresentationPlan.make(
            source: .photoLibrary,
            isCameraAvailable: {
                cameraAvailabilityCalls += 1
                return false
            }
        )

        guard case let .photoLibraryPicker(configuration) = plan else {
            return XCTFail("Expected photo library picker.")
        }
        XCTAssertEqual(cameraAvailabilityCalls, 0)
        XCTAssertEqual(configuration.selectionLimit, 0)
        XCTAssertNotNil(configuration.filter)
        XCTAssertEqual(configuration.preferredAssetRepresentationMode, .current)
    }

    func testDocumentSourceBuildsItemCopyMultipleSelectionPlan() {
        var cameraAvailabilityCalls = 0

        let plan = ChatAttachmentPickerPresentationPlan.make(
            source: .documents,
            isCameraAvailable: {
                cameraAvailabilityCalls += 1
                return false
            }
        )

        guard case let .documentPicker(contentTypes, asCopy, allowsMultipleSelection) = plan else {
            return XCTFail("Expected document picker.")
        }
        XCTAssertEqual(cameraAvailabilityCalls, 0)
        XCTAssertEqual(contentTypes, [.item])
        XCTAssertTrue(asCopy)
        XCTAssertTrue(allowsMultipleSelection)
    }
}

private extension ChatAttachmentPickerPresentationPlan {
    var errorMessage: String? {
        guard case let .error(message) = self else {
            return nil
        }

        return message
    }
}
