//
//  StoreNotificationObserver.swift
//  UniLLMsTests
//

import Foundation
@testable import UniLLMs

final class StoreNotificationObserver {
    private var token: NSObjectProtocol?
    private let notificationCenter: NotificationCenter
    private weak var observedObject: AnyObject?
    private(set) var notificationCount = 0

    init(
        name: Notification.Name,
        object: AnyObject,
        notificationCenter: NotificationCenter
    ) {
        self.notificationCenter = notificationCenter
        observedObject = object
        token = notificationCenter.addObserver(
            forName: name,
            object: object,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  notification.object as AnyObject === observedObject else {
                return
            }

            notificationCount += 1
        }
    }

    func invalidate() {
        if let token {
            notificationCenter.removeObserver(token)
        }
        token = nil
    }

    deinit {
        invalidate()
    }
}
