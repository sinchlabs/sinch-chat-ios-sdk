//  RelaySwitchTests.swift — the relay off switch.

import XCTest

@testable import SinchPushSDK

final class RelaySwitchTests: XCTestCase {

    /// A private suite per test, so nothing leaks into `UserDefaults.standard`.
    private func freshDefaults() -> UserDefaults {
        let name = "RelaySwitchTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    // MARK: - The store

    func testTheUserDefaultsStoreDefaultsToOnUnderTheDocumentedKey() {
        let defaults = freshDefaults()
        let store = UserDefaultsRelaySwitchStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled, "a missing key means never switched off")
        XCTAssertEqual(UserDefaultsRelaySwitchStore.key, "com.sinch.push.relay.enabled")

        store.setEnabled(false)
        XCTAssertEqual(defaults.object(forKey: "com.sinch.push.relay.enabled") as? Bool, false)
    }

    func testTheSwitchSurvivesANewStoreOverTheSameDefaults() {
        let defaults = freshDefaults()
        UserDefaultsRelaySwitchStore(defaults: defaults).setEnabled(false)

        XCTAssertFalse(UserDefaultsRelaySwitchStore(defaults: defaults).isEnabled)

        UserDefaultsRelaySwitchStore(defaults: defaults).setEnabled(true)
        XCTAssertTrue(UserDefaultsRelaySwitchStore(defaults: defaults).isEnabled)
    }

    func testTheInMemoryStoreDefaultsToOnAndKeepsTheLastValue() {
        let store = InMemoryRelaySwitchStore()
        XCTAssertTrue(store.isEnabled)
        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
        XCTAssertFalse(InMemoryRelaySwitchStore(enabled: false).isEnabled)
    }

    // MARK: - The device-info provider

    func testTheProviderReportsRelayDisabledWhileOffAndUnsupportedOtherwise() {
        let relaySwitch = InMemoryRelaySwitchStore()
        let provider = SystemDeviceInfoProvider(
            installationId: { "id" }, relaySwitch: relaySwitch)

        XCTAssertEqual(provider.current(sdkVersionOverride: nil).backgroundService, .unsupported)

        relaySwitch.setEnabled(false)
        XCTAssertEqual(provider.current(sdkVersionOverride: nil).backgroundService, .relayDisabled)

        relaySwitch.setEnabled(true)
        XCTAssertEqual(provider.current(sdkVersionOverride: nil).backgroundService, .unsupported)
    }

    func testAProviderBuiltWithoutASwitchReportsUnsupported() {
        let provider = SystemDeviceInfoProvider(installationId: { "id" })
        XCTAssertEqual(provider.current(sdkVersionOverride: nil).backgroundService, .unsupported)
    }
}
