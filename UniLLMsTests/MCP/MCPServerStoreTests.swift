//
//  MCPServerStoreTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class MCPServerStoreTests: UserDefaultsBackedTestCase {
    @MainActor
    func testMCPServerStorePersistsServers() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        var server = mcpStore.makeServerDraft()
        XCTAssertEqual(server.name, "")

        server.name = "Team Tools"
        server.configuration = MCPServerConfiguration(
            endpoint: "https://example.com/mcp",
            headers: ["Authorization": "Bearer test"],
            timeout: 30,
            isEnabled: true
        )

        mcpStore.saveServerRecord(server)

        let reloadedStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        let reloadedServer = reloadedStore.loadServers().first

        XCTAssertEqual(reloadedServer?.id, server.id)
        XCTAssertEqual(reloadedServer?.name, "Team Tools")
        XCTAssertEqual(reloadedServer?.configuration.endpoint, "https://example.com/mcp")
        XCTAssertEqual(reloadedServer?.configuration.headers["Authorization"], "Bearer test")
        XCTAssertEqual(reloadedServer?.configuration.timeout, 30)
        XCTAssertEqual(reloadedServer?.configuration.isEnabled, true)
    }

    @MainActor
    func testMCPServerStoreUpdatesMatchingUUID() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        var server = MCPServerRecord(name: "Old")
        mcpStore.saveServerRecord(server)

        server.name = "New"
        server.configuration.endpoint = "https://example.com/mcp"
        mcpStore.saveServerRecord(server)

        XCTAssertEqual(mcpStore.loadServers(), [server])
    }

    @MainActor
    func testMCPServerStoreDeletesMatchingUUIDOnly() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        let first = MCPServerRecord(name: "First")
        let second = MCPServerRecord(name: "Second")
        mcpStore.saveServerRecord(first)
        mcpStore.saveServerRecord(second)

        mcpStore.deleteServerRecord(id: first.id)

        XCTAssertEqual(mcpStore.loadServers(), [second])
    }

    @MainActor
    func testMCPServerStoreMovesValidIndicesAndIgnoresInvalidMoves() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        let first = MCPServerRecord(name: "First")
        let second = MCPServerRecord(name: "Second")
        let third = MCPServerRecord(name: "Third")
        [first, second, third].forEach(mcpStore.saveServerRecord)

        mcpStore.moveServer(from: 0, to: 2)

        XCTAssertEqual(mcpStore.loadServers().map(\.id), [second.id, third.id, first.id])

        mcpStore.moveServer(from: 99, to: 0)
        mcpStore.moveServer(from: 1, to: 1)

        XCTAssertEqual(mcpStore.loadServers().map(\.id), [second.id, third.id, first.id])
    }
}
