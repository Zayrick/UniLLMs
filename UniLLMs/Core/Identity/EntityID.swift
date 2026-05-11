//
//  EntityID.swift
//  UniLLMs
//
//  Provides an owner-typed entity identifier wrapper for future strongly typed identity modeling.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

nonisolated struct EntityID<Owner>: Codable, Hashable, Equatable {
    var rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
