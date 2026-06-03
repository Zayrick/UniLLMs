//
//  ChatMarkdownTypography.swift
//  UniLLMs
//
//  Shared typography helpers for chat Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

enum ChatMarkdownFontTraits {
    private static let syntheticItalicObliqueness = NSNumber(value: 0.3)

    static func adding(
        _ traits: UIFontDescriptor.SymbolicTraits,
        to font: UIFont
    ) -> UIFont {
        guard !traits.isEmpty else {
            return font
        }

        let requestedTraits = font.fontDescriptor.symbolicTraits.union(traits)
        var requestedFontTraits = requestedTraits
        requestedFontTraits.remove(.traitItalic)

        let requiredFontTraits = requestedFontTraits.intersection([.traitBold])
        guard !requiredFontTraits.isEmpty else {
            return font
        }

        if let descriptor = font.fontDescriptor.withSymbolicTraits(requestedFontTraits) {
            let resolvedFont = UIFont(descriptor: descriptor, size: font.pointSize)
            if resolvedFont.fontDescriptor.symbolicTraits.contains(requiredFontTraits) {
                return resolvedFont
            }
        }

        return fallbackFont(applying: requiredFontTraits, to: font)
    }

    static func applyItalicObliquenessIfNeeded(
        to attributes: inout [NSAttributedString.Key: Any],
        requestedTraits: UIFontDescriptor.SymbolicTraits
    ) {
        guard requestedTraits.contains(.traitItalic) else {
            return
        }

        attributes[.obliqueness] = syntheticItalicObliqueness
    }

    private static func fallbackFont(
        applying traits: UIFontDescriptor.SymbolicTraits,
        to font: UIFont
    ) -> UIFont {
        guard !traits.isEmpty else {
            return font
        }

        if traits.contains(.traitBold) {
            return addingBold(to: font)
        }

        return font
    }

    private static func addingBold(to font: UIFont) -> UIFont {
        let boldTraits = font.fontDescriptor.symbolicTraits.union(.traitBold)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(boldTraits) {
            let resolvedFont = UIFont(descriptor: descriptor, size: font.pointSize)
            if resolvedFont.fontDescriptor.symbolicTraits.contains(.traitBold) {
                return resolvedFont
            }
        }

        return .boldSystemFont(ofSize: font.pointSize)
    }
}
