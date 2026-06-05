//
//  UserDefaultsStoreFailureObserver.swift
//  UniLLMsTests
//

import Foundation
@testable import UniLLMs

final class UserDefaultsStoreFailureObserver {
    private var token: NSObjectProtocol?
    private let notificationCenter: NotificationCenter
    private(set) var failures: [UserDefaultsStoreFailure] = []

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
        token = notificationCenter.addObserver(
            forName: UserDefaultsStore.didFailNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let failure = notification.userInfo?[
                UserDefaultsStore.failureUserInfoKey
            ] as? UserDefaultsStoreFailure else {
                return
            }

            self?.failures.append(failure)
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
