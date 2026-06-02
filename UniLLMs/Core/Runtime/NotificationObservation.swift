//
//  NotificationObservation.swift
//  UniLLMs
//
//  Created by OpenAI on 2026/6/2.
//

import Foundation

nonisolated final class NotificationObservation {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol, center: NotificationCenter = .default) {
        self.center = center
        self.token = token
    }

    deinit {
        center.removeObserver(token)
    }
}
