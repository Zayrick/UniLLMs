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
        XCTAssertEqual(store.reasoningEffortConfigurationValue, -1)
        XCTAssertNil(store.selectedSystemPromptID)
    }

    func testAppSettingsPersistColorModeAndIdleSleepPreference() {
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let promptID = UUID()
        store.colorMode = .dark
        store.keepsScreenAwakeDuringAIOutput = true
        store.reasoningEffortConfigurationValue = 8
        store.selectedSystemPromptID = promptID

        let reloadedStore = UserDefaultsAppSettingsStore(defaults: defaults)

        XCTAssertEqual(reloadedStore.colorMode, .dark)
        XCTAssertTrue(reloadedStore.keepsScreenAwakeDuringAIOutput)
        XCTAssertEqual(reloadedStore.reasoningEffortConfigurationValue, 8)
        XCTAssertEqual(reloadedStore.selectedSystemPromptID, promptID)
    }
}
