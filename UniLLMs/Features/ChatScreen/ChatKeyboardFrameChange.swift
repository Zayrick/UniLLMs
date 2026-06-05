//
//  ChatKeyboardFrameChange.swift
//  UniLLMs
//
//  Converts UIKit keyboard notifications into the layout facts used by the chat composer.
//  Created by Codex on 2026/6/5.
//

import UIKit

struct ChatKeyboardFrameChange: Equatable {
    var endFrame: CGRect
    var screenBounds: CGRect
    var animationDuration: TimeInterval
    var animationCurveRawValue: UInt

    var isKeyboardVisible: Bool {
        endFrame.minY < screenBounds.maxY
    }

    var animationOptions: UIView.AnimationOptions {
        UIView.AnimationOptions(rawValue: animationCurveRawValue << 16)
            .union(.beginFromCurrentState)
    }

    init(
        endFrame: CGRect,
        screenBounds: CGRect,
        animationDuration: TimeInterval,
        animationCurveRawValue: UInt
    ) {
        self.endFrame = endFrame
        self.screenBounds = screenBounds
        self.animationDuration = animationDuration
        self.animationCurveRawValue = animationCurveRawValue
    }

    init?(
        notification: Notification,
        screenBounds: CGRect
    ) {
        guard let userInfo = notification.userInfo,
              let endFrameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let animationDurationValue = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else {
            return nil
        }

        let animationCurveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
        self.init(
            endFrame: endFrameValue.cgRectValue,
            screenBounds: screenBounds,
            animationDuration: animationDurationValue.doubleValue,
            animationCurveRawValue: animationCurveValue?.uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        )
    }
}
