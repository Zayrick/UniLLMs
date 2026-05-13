//
//  ChatMarkdownTypography.swift
//  UniLLMs
//
//  Shared typography helpers for chat Markdown rendering.
//  Created by Zayrick on 2026/5/13.
//

import UIKit

enum ChatMarkdownFontTraits {
    static func adding(
        _ traits: UIFontDescriptor.SymbolicTraits,
        to font: UIFont
    ) -> UIFont {
        guard !traits.isEmpty,
              let descriptor = font.fontDescriptor.withSymbolicTraits(
                font.fontDescriptor.symbolicTraits.union(traits)
              ) else {
            return fallbackFont(adding: traits, to: font)
        }

        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func fallbackFont(
        adding traits: UIFontDescriptor.SymbolicTraits,
        to font: UIFont
    ) -> UIFont {
        guard !traits.isEmpty else {
            return font
        }

        if traits.contains(.traitBold), traits.contains(.traitItalic),
           let descriptor = UIFont.boldSystemFont(ofSize: font.pointSize)
            .fontDescriptor
            .withSymbolicTraits([.traitBold, .traitItalic]) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }

        if traits.contains(.traitBold) {
            return .boldSystemFont(ofSize: font.pointSize)
        }

        if traits.contains(.traitItalic) {
            return .italicSystemFont(ofSize: font.pointSize)
        }

        return font
    }
}
