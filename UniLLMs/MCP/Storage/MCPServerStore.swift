//
//  MCPServerStore.swift
//  UniLLMs
//
//  Declares MCP server configuration storage protocols; currently an architectural placeholder for future MCP persistence.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

protocol MCPServerStore {
    func fetchServers() async throws -> [MCPServerRecord]
    func saveServer(_ server: MCPServerRecord) async throws
    func deleteServer(id: UUID) async throws
}
