//
//  AppError.swift
//  UniLLMs
//
//  Defines shared application errors for lightweight cross-module failure reporting.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

enum AppError: LocalizedError, Equatable {
    case unavailable(String)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message),
             let .invalidState(message):
            return message
        }
    }
}
