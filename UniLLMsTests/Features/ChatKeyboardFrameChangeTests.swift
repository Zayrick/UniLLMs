//
//  ChatKeyboardFrameChangeTests.swift
//  UniLLMsTests
//

import UIKit
import XCTest
@testable import UniLLMs

final class ChatKeyboardFrameChangeTests: XCTestCase {
    func testKeyboardFrameChangeParsesNotificationLayoutFacts() throws {
        let notification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(
                    cgRect: CGRect(x: 0, y: 500, width: 390, height: 344)
                ),
                UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.25),
                UIResponder.keyboardAnimationCurveUserInfoKey: NSNumber(
                    value: UIView.AnimationCurve.easeOut.rawValue
                )
            ]
        )

        let frameChange = try XCTUnwrap(
            ChatKeyboardFrameChange(
                notification: notification,
                screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844)
            )
        )

        XCTAssertTrue(frameChange.isKeyboardVisible)
        XCTAssertEqual(frameChange.endFrame, CGRect(x: 0, y: 500, width: 390, height: 344))
        XCTAssertEqual(frameChange.animationDuration, 0.25)
        XCTAssertEqual(
            frameChange.animationOptions,
            UIView.AnimationOptions(rawValue: UInt(UIView.AnimationCurve.easeOut.rawValue) << 16)
                .union(.beginFromCurrentState)
        )
    }

    func testKeyboardFrameChangeTreatsKeyboardAtScreenBottomAsHidden() {
        let frameChange = ChatKeyboardFrameChange(
            endFrame: CGRect(x: 0, y: 844, width: 390, height: 344),
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            animationDuration: 0.25,
            animationCurveRawValue: UInt(UIView.AnimationCurve.easeInOut.rawValue)
        )

        XCTAssertFalse(frameChange.isKeyboardVisible)
    }

    func testKeyboardFrameChangeRejectsMissingRequiredUserInfo() {
        let notification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.25)
            ]
        )

        XCTAssertNil(
            ChatKeyboardFrameChange(
                notification: notification,
                screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844)
            )
        )
    }
}
