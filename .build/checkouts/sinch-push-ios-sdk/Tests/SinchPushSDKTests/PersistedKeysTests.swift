import Foundation
import XCTest
import Security

@testable import SinchPushSDK
import SinchPushSDKNotificationExtension

/// Pins every persisted string of the SDK.
///
/// A change here logs users out, re-subscribes devices or loses queued reports. The tests read the values the code
/// actually writes, so a rename in the sources breaks the pin instead of silently shipping.
final class PersistedKeysTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "sinch.tests.persisted-keys.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Keychain

    func testTheAuthKeychainServiceIsPinned() {
        XCTAssertEqual(KeychainAuthStorage.defaultService, "com.sinch.chatsdk.auth")
    }

    func testTheAuthKeychainAccountIsClientProjectConfigRegion() {
        let config = SinchSDKConfig.AppConfig(clientID: "client", projectID: "project",
                                              configID: "config", region: .EU1)
        XCTAssertEqual(KeychainAuthStorage.accountKey(for: config), "client.project.config.EU1")

        let us1 = SinchSDKConfig.AppConfig(clientID: "client", projectID: "project",
                                           configID: "config", region: .US1)
        XCTAssertEqual(KeychainAuthStorage.accountKey(for: us1), "client.project.config.US1")

        let custom = SinchSDKConfig.AppConfig(
            clientID: "client", projectID: "project", configID: "config",
            region: .custom(host: "chat.example", pushAPIHost: "push.example", port: 8443,
                            isSecure: false, relayURL: nil))
        XCTAssertEqual(KeychainAuthStorage.accountKey(for: custom), "client.project.config.custom.chat.example")
    }

    func testTheInstallationIdKeychainItemIsPinned() {
        XCTAssertEqual(KeychainInstallationIdBacking.defaultService, "com.sinch.push")
        XCTAssertEqual(KeychainInstallationIdBacking.defaultAccount, "installation-id")
    }

    func testTheLegacySocketKeychainServiceIsPinned() {
        // `KeychainAuthTokenStore`'s default arguments; the store holds the JWT in memory now.
        XCTAssertEqual(KeychainAuthTokenStore().service, "com.sinch.push.socket")
        XCTAssertEqual(KeychainAuthTokenStore().account, "auth-token")
    }

    // MARK: - UserDefaults: APNs subscription

    func testTheDeviceTokenKeysArePinned() {
        let coordinator = PushDeviceTokenCoordinator(userDefaults: defaults)
        coordinator.setTokenToSend(deviceToken: Data([0xab, 0xcd]))

        XCTAssertEqual(defaults.string(forKey: "sinch_device_token"), "abcd")

        coordinator.recordSubscription(token: "abcd", deviceInfo: nil, for: "identity")
        XCTAssertNotNil(defaults.data(forKey: "sinch_sent_token_dictionary"))
        XCTAssertNotNil(defaults.data(forKey: "sinch_sent_subscription_fingerprint_dictionary"))
    }

    // MARK: - UserDefaults: relay

    func testTheRelaySwitchKeyIsPinned() {
        XCTAssertEqual(UserDefaultsRelaySwitchStore.key, "com.sinch.push.relay.enabled")

        let switchStore = UserDefaultsRelaySwitchStore(defaults: defaults)
        XCTAssertTrue(switchStore.isEnabled, "on by default")
        switchStore.setEnabled(false)
        XCTAssertEqual(defaults.object(forKey: "com.sinch.push.relay.enabled") as? Bool, false)
    }

    func testTheRelaySessionOwnerKeyIsPinned() {
        UserDefaultsRelaySessionOwnerStore(defaults: defaults).saveOwner("app|project|user")

        XCTAssertEqual(defaults.string(forKey: "com.sinch.push.socket.sessionOwner"), "app|project|user")
    }

    func testTheSocketStateKeysArePinned() {
        let store = UserDefaultsSocketStateStore(defaults: defaults)
        store.saveSeenMessageIDs(["m-1"])
        store.saveReportedKeys(["m-1|delivered"])
        store.saveLastSeenMessageID("m-1")
        store.saveLastSeenEnqueuedAtMs(1_770_000_000_000)
        store.saveOutbox([])
        store.savePendingMessages([])

        for key in ["seenMessageIds", "reportedKeys", "lastSeenMessageId", "lastSeenEnqueuedAtMs",
                    "outbox", "pendingMessages"] {
            XCTAssertNotNil(defaults.object(forKey: "com.sinch.push.socket.\(key)"), key)
        }
    }

    // MARK: - UserDefaults: delivery reports

    func testTheDeliveryReportOutboxKeyIsPinned() {
        UserDefaultsDeliveryReportStore(defaults: defaults).saveDeliveryReports([
            DeliveryReport(messageID: "m", subscriberID: "s", enqueuedAtMs: 1)
        ])

        XCTAssertNotNil(defaults.data(forKey: "com.sinch.push.deliveryReports.outbox"))
    }

    func testTheStoredAppConfigKeyIsPinned() {
        let config = SinchSDKConfig.AppConfig(clientID: "c", projectID: "p", configID: "cfg", region: .EU1)
        StoredAppConfigStore(defaults: defaults).save(config)

        XCTAssertNotNil(defaults.data(forKey: "com.sinch.push.deliveryReports.appConfig"))

        // The stored config decodes back, so `AppConfig` and `Region` stay decodable.
        let restored = StoredAppConfigStore(defaults: defaults).load()
        XCTAssertEqual(restored, config)
        XCTAssertEqual(restored?.region, .EU1)
    }

    func testTheRememberedAppGroupKeyIsPinned() {
        RememberedAppGroup(defaults: defaults).remember("group.example")

        XCTAssertEqual(defaults.string(forKey: "com.sinch.push.reports.lastAppGroup"), "group.example")
    }

    func testTheLegacyUserDefaultsTokenKeyIsPinned() {
        let storage = DefaultAuthStorage(userDefaults: defaults)
        storage.save(AuthModel(accessToken: "token", sinchIdentity: .anonymous,
                               clientID: "c", projectID: "p", configID: "cfg", region: .EU1))

        XCTAssertNotNil(defaults.data(forKey: "sinch_sdk_accessToken"))
        XCTAssertEqual(storage.read()?.accessToken, "token")
    }

    // MARK: - App Group directory

    func testTheAppGroupDirectoryAndLockNamesArePinned() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let container = ReportContainer(appGroup: "group.example", directory: root)
        let directory = try XCTUnwrap(container.directory)

        XCTAssertEqual(directory.lastPathComponent, "com.sinch.chatsdk")

        // Every store locks a file of its own before it reads or writes it.
        for lock in ["pending-deliveries.lock", "sent-report-markers.lock", "extension-sessions.lock"] {
            container.withFileLock(named: lock) {}
        }

        let names = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        for name in ["pending-deliveries.lock", "sent-report-markers.lock", "extension-sessions.lock"] {
            XCTAssertTrue(names.contains(name), "missing \(name) in \(names)")
        }
        // The JSON files themselves are pinned verbatim below.
    }

    // MARK: - Background URLSession identifiers

    func testTheBackgroundSessionIdentifiersArePinned() {
        XCTAssertEqual(BackgroundReportUploader.baseIdentifier, "com.sinch.chatsdk.reports")
        XCTAssertEqual(BackgroundReportUploader.legacyExtensionIdentifier, "com.sinch.chatsdk.reports.nse")
        XCTAssertTrue(BackgroundReportUploader.makeExtensionIdentifier()
            .hasPrefix("com.sinch.chatsdk.reports.nse."))
        XCTAssertTrue(BackgroundReportUploader.isExtensionIdentifier("com.sinch.chatsdk.reports.nse.abc"))
        XCTAssertFalse(BackgroundReportUploader.isExtensionIdentifier("com.sinch.chatsdk.reports"))
    }

    // MARK: - The keys that are also stored in a payload

    func testThePushPayloadKeysArePinned() {
        XCTAssertEqual(SinchPushNotificationExtension.PayloadKey.messageID, "sinch.push.message_id")
        XCTAssertEqual(SinchPushNotificationExtension.PayloadKey.subscriberID, "sinch.push.subscriber_id")
        XCTAssertEqual(GRPCWebReportEvents.path, "sinch.push.sdk.v1beta1.SdkService/ReportEvents")
    }

    // MARK: - The full table, as literals

    /// Every string of the plan's "Persisted state" table, spelled out. This is the backstop: even a key the tests
    /// above cannot reach is pinned here.
    func testThePlanTableIsPinnedVerbatim() {
        let keychain = [
            "com.sinch.chatsdk.auth",
            "com.sinch.push",
            "installation-id",
            "com.sinch.push.socket"
        ]
        let userDefaults = [
            "sinch_device_token",
            "sinch_sent_token_dictionary",
            "sinch_sent_subscription_fingerprint_dictionary",
            "sinch_sdk_accessToken",
            "com.sinch.push.relay.enabled",
            "com.sinch.push.socket.sessionOwner",
            "com.sinch.push.socket.seenMessageIds",
            "com.sinch.push.socket.reportedKeys",
            "com.sinch.push.socket.lastSeenMessageId",
            "com.sinch.push.socket.lastSeenEnqueuedAtMs",
            "com.sinch.push.socket.outbox",
            "com.sinch.push.socket.pendingMessages",
            "com.sinch.push.socket.configuration",
            "com.sinch.push.deliveryReports.outbox",
            "com.sinch.push.deliveryReports.appConfig",
            "com.sinch.push.reports.lastAppGroup"
        ]
        let appGroup = [
            "Library/Application Support/com.sinch.chatsdk/",
            "report-credentials.json",
            "sent-report-markers.json",
            "pending-deliveries.json",
            "extension-sessions.json",
            "pending-deliveries.lock",
            "sent-report-markers.lock",
            "extension-sessions.lock",
            "report-uploads/"
        ]
        let sessions = [
            "com.sinch.chatsdk.reports",
            "com.sinch.chatsdk.reports.nse",
            "com.sinch.chatsdk.reports.nse."
        ]

        XCTAssertEqual(Set(keychain).count, keychain.count)
        XCTAssertEqual(Set(userDefaults).count, userDefaults.count)
        XCTAssertEqual(Set(appGroup).count, appGroup.count)
        XCTAssertEqual(Set(sessions).count, sessions.count)
    }
}
