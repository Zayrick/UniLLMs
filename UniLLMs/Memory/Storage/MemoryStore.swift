//
//  MemoryStore.swift
//  UniLLMs
//
//  Declares memory storage protocols; currently an architectural placeholder for future memory persistence or indexed storage.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol MemoryStore {
    func fetchMemories(scope: MemoryScope?) async throws -> [MemoryRecord]
    func saveMemory(_ memory: MemoryRecord) async throws
    func deleteMemory(id: UUID) async throws
}
