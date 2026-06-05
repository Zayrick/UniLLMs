//
//  MCPServerStoreTests.swift
//  UniLLMsTests
//

import Foundation
import UIKit
import XCTest
@testable import UniLLMs

final class MCPServerStoreTests: UserDefaultsBackedTestCase {
    func testMCPServerStorePersistsServers() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        var server = makeServer(name: "")
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

    func testMCPServerStoreUpdatesMatchingUUID() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        var server = makeServer(name: "Old")
        mcpStore.saveServerRecord(server)

        server.name = "New"
        server.configuration.endpoint = "https://example.com/mcp"
        mcpStore.saveServerRecord(server)

        XCTAssertEqual(mcpStore.loadServers(), [server])
    }

    func testMCPServerStoreDeletesMatchingUUIDOnly() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        let first = makeServer(name: "First")
        let second = makeServer(name: "Second")
        mcpStore.saveServerRecord(first)
        mcpStore.saveServerRecord(second)

        mcpStore.deleteServerRecord(id: first.id)

        XCTAssertEqual(mcpStore.loadServers(), [second])
    }

    func testMCPServerStoreMovesValidIndicesAndIgnoresInvalidMoves() {
        let mcpStore = UserDefaultsMCPServerStore(defaults: defaults, storageKey: "mcpServers")
        let first = makeServer(name: "First")
        let second = makeServer(name: "Second")
        let third = makeServer(name: "Third")
        [first, second, third].forEach(mcpStore.saveServerRecord)

        mcpStore.moveServer(from: 0, to: 2)

        XCTAssertEqual(mcpStore.loadServers().map(\.id), [second.id, third.id, first.id])

        mcpStore.moveServer(from: 99, to: 0)
        mcpStore.moveServer(from: 1, to: 1)

        XCTAssertEqual(mcpStore.loadServers().map(\.id), [second.id, third.id, first.id])
    }

    func testMCPServerStorePostsOnlyOnInjectedNotificationCenter() {
        let notificationCenter = NotificationCenter()
        let mcpStore = UserDefaultsMCPServerStore(
            defaults: defaults,
            notificationCenter: notificationCenter,
            storageKey: "mcpServers"
        )
        let injectedObserver = StoreNotificationObserver(
            name: UserDefaultsMCPServerStore.didChangeNotification,
            object: mcpStore,
            notificationCenter: notificationCenter
        )
        let defaultObserver = StoreNotificationObserver(
            name: UserDefaultsMCPServerStore.didChangeNotification,
            object: mcpStore,
            notificationCenter: .default
        )
        defer {
            injectedObserver.invalidate()
            defaultObserver.invalidate()
        }

        mcpStore.saveServerRecord(makeServer(name: "Team Tools"))

        XCTAssertEqual(injectedObserver.notificationCount, 1)
        XCTAssertEqual(defaultObserver.notificationCount, 0)
    }

    private func makeServer(name: String) -> MCPServerRecord {
        MCPServerRecord(name: name, createdAt: Date(timeIntervalSince1970: 1))
    }
}
