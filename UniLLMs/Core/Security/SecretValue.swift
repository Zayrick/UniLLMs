//
//  SecretValue.swift
//  UniLLMs
//
//  Wraps sensitive strings with safe display semantics to avoid exposing secrets in debug output.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct SecretValue: Codable, Equatable, CustomStringConvertible {
    var rawValue: String

    var description: String {
        rawValue.isEmpty ? "" : "••••••••"
    }
}
