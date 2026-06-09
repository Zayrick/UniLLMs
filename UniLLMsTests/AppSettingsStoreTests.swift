//
//  AppSettingsStoreTests.swift
//  UniLLMsTests
//

import XCTest
@testable import UniLLMs

final class AppSettingsStoreTests: UserDefaultsBackedTestCase {
    func testDefaultSettingsUseSystemAppearanceAndAllowIdleSleep() {
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.colorMode, .system)
        XCTAssertFalse(store.keepsScreenAwakeDuringAIOutput)
    }

    func testAppSettingsPersistColorModeAndIdleSleepPreference() {
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        store.colorMode = .dark
        store.keepsScreenAwakeDuringAIOutput = true

        let reloadedStore = UserDefaultsAppSettingsStore(defaults: defaults)

        XCTAssertEqual(reloadedStore.colorMode, .dark)
        XCTAssertTrue(reloadedStore.keepsScreenAwakeDuringAIOutput)
    }
}
