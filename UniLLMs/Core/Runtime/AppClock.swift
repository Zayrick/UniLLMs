//
//  AppClock.swift
//  UniLLMs
//
//  Defines an abstract time source and system implementation for future runtime replacement or tests.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated protocol AppClock {
    var now: Date { get }
}

nonisolated struct SystemAppClock: AppClock {
    var now: Date {
        Date()
    }
}
