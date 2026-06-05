//
//  ChatSideMenuPageGeometry.swift
//  UniLLMs
//
//  Describes the main chat page geometry while the side menu opens and closes.
//  Created by Codex on 2026/6/5.
//

import UIKit

struct ChatSideMenuPageGeometry: Equatable {
    var pageTranslationX: CGFloat
    var pageAlpha: CGFloat
    var pageCornerRadius: CGFloat
    var pageMasksToBounds: Bool
    var sideMenuAlpha: CGFloat
    var dismissControlAlpha: CGFloat
    var shadowOpacity: Float

    static func make(
        isOpen: Bool,
        pageWidth: CGFloat,
        revealRatio: CGFloat,
        openPageOpacity: CGFloat,
        openCornerRadius: CGFloat,
        openShadowOpacity: Float
    ) -> ChatSideMenuPageGeometry {
        guard isOpen else {
            return ChatSideMenuPageGeometry(
                pageTranslationX: 0.0,
                pageAlpha: 1.0,
                pageCornerRadius: 0.0,
                pageMasksToBounds: false,
                sideMenuAlpha: 0.0,
                dismissControlAlpha: 0.0,
                shadowOpacity: 0.0
            )
        }

        return ChatSideMenuPageGeometry(
            pageTranslationX: pageWidth * revealRatio,
            pageAlpha: openPageOpacity,
            pageCornerRadius: openCornerRadius,
            pageMasksToBounds: true,
            sideMenuAlpha: 1.0,
            dismissControlAlpha: 1.0,
            shadowOpacity: openShadowOpacity
        )
    }
}
