//
//  ChatMarkdownTextFadeMaskPlan.swift
//  UniLLMs
//
//  Plans fade mask geometry for appended Markdown text.
//

import UIKit

nonisolated struct ChatMarkdownTextFadeMaskPlan: Equatable {
    nonisolated struct LineFragment: Equatable {
        var changedRect: CGRect
        var lineFrame: CGRect
        var usedFrame: CGRect
    }

    private let bounds: CGRect
    private let minimumLayerSize: CGFloat
    private let fragments: [LineFragment]

    init(
        bounds: CGRect,
        minimumLayerSize: CGFloat,
        fragments: [LineFragment]
    ) {
        self.bounds = bounds
        self.minimumLayerSize = minimumLayerSize
        self.fragments = fragments
    }

    var opaqueFrames: [CGRect] {
        guard let firstFragment = fragments.first else {
            return []
        }

        let lineFrame = firstFragment.lineFrame
        let fadeFrame = fadeFrame(for: firstFragment)
        return [
            CGRect(
                x: 0.0,
                y: 0.0,
                width: bounds.width,
                height: max(0.0, lineFrame.minY)
            ),
            CGRect(
                x: 0.0,
                y: lineFrame.minY,
                width: max(0.0, fadeFrame.minX),
                height: lineFrame.height
            )
        ].filter(isVisibleLayerFrame)
    }

    var fadeFrames: [CGRect] {
        fragments
            .map(fadeFrame)
            .filter(isVisibleLayerFrame)
    }

    var isEmpty: Bool {
        fadeFrames.isEmpty
    }

    private func fadeFrame(for fragment: LineFragment) -> CGRect {
        let effectiveChangedRect = fragment.changedRect.isNull || !fragment.changedRect.hasFiniteCoordinates
            ? fragment.usedFrame
            : fragment.changedRect
        let y = max(0.0, min(fragment.lineFrame.minY, bounds.height))
        let height = max(
            0.0,
            min(fragment.lineFrame.height, bounds.height - y)
        )
        let minX = max(
            0.0,
            min(effectiveChangedRect.minX, bounds.width)
        )
        let maxX = max(
            minX,
            min(max(effectiveChangedRect.maxX, fragment.usedFrame.maxX), bounds.width)
        )
        return CGRect(x: minX, y: y, width: maxX - minX, height: height)
    }

    private func isVisibleLayerFrame(_ frame: CGRect) -> Bool {
        frame.width > minimumLayerSize &&
            frame.height > minimumLayerSize
    }
}

private extension CGRect {
    nonisolated var hasFiniteCoordinates: Bool {
        origin.x.isFinite &&
            origin.y.isFinite &&
            size.width.isFinite &&
            size.height.isFinite
    }
}
