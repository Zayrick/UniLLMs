//
//  ChatAttachmentPickerPresentationPlan.swift
//  UniLLMs
//
//  Describes which attachment picker should be presented for a composer add source.
//

import Foundation
import PhotosUI
import UniformTypeIdentifiers

enum ChatAttachmentAcquisitionSource {
    case camera
    case photoLibrary
    case documents
}

enum ChatAttachmentPickerPresentationPlan {
    case cameraPicker
    case photoLibraryPicker(PHPickerConfiguration)
    case documentPicker(
        contentTypes: [UTType],
        asCopy: Bool,
        allowsMultipleSelection: Bool
    )
    case error(String)

    @MainActor
    static func make(
        source: ChatAttachmentAcquisitionSource,
        isCameraAvailable: () -> Bool
    ) -> ChatAttachmentPickerPresentationPlan {
        switch source {
        case .camera:
            guard isCameraAvailable() else {
                return .error(String(localized: .chatAttachmentCameraUnavailable))
            }
            return .cameraPicker
        case .photoLibrary:
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .images
            configuration.selectionLimit = 0
            configuration.preferredAssetRepresentationMode = .current
            return .photoLibraryPicker(configuration)
        case .documents:
            return .documentPicker(
                contentTypes: [.item],
                asCopy: true,
                allowsMultipleSelection: true
            )
        }
    }
}
