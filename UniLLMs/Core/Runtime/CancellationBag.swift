//
//  CancellationBag.swift
//  UniLLMs
//
//  Collects cancellation closures so views and runtimes can release asynchronous work together.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

final class CancellationBag {
    private var cancellations: [() -> Void] = []

    func insert(_ cancellation: @escaping () -> Void) {
        cancellations.append(cancellation)
    }

    func cancelAll() {
        let pendingCancellations = cancellations
        cancellations.removeAll()
        pendingCancellations.forEach { $0() }
    }
}
