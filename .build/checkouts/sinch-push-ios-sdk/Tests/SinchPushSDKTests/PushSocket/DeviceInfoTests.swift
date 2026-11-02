import XCTest

@testable import SinchPushSDK

final class DeviceInfoTests: XCTestCase {

    private final class FailingStore: InstallationIdStore {
        func installationId() throws -> String {
            throw InstallationIdError.unavailable(reason: "the keychain returned status -25308")
        }
    }

    func testLiveWiringReadsTheInstallationIdStoreAndTheSDKVersion() {
        let id = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
        let provider = SystemDeviceInfoProvider.live(
            installationIdStore: KeychainInstallationIdStore(
                backing: InMemoryInstallationIdBacking(id: id), logger: SilentSocketLogger()),
            logger: SilentSocketLogger())

        let info = provider.current(sdkVersionOverride: nil)

        XCTAssertEqual(info.installationId, id)
        XCTAssertEqual(info.platform, .ios)
        XCTAssertEqual(info.sdkVersion, SinchPushSDK.version)
        XCTAssertFalse(info.sdkVersion.isEmpty)
        XCTAssertFalse(info.osVersion.isEmpty)
        XCTAssertEqual(info.backgroundService, .unsupported)
    }

    func testTheDefaultSDKVersionIsTheOneTheGRPCMetadataSends() {
        XCTAssertEqual(SocketConfiguration.defaultSDKVersion, SinchPushSDK.version)
    }

    func testAnUnavailableInstallationIdIsEmptyAndLeavesTheRestIntact() {
        let logger = RecordingLogger()
        let provider = SystemDeviceInfoProvider.live(installationIdStore: FailingStore(), logger: logger)

        let info = provider.current(sdkVersionOverride: nil)

        XCTAssertEqual(info.installationId, "")
        XCTAssertNil(info.subscribable)
        XCTAssertEqual(info.sdkVersion, SinchPushSDK.version)
        XCTAssertTrue(logger.contains("installation id unavailable"))
    }

    func testSubscribableNeedsANonEmptyInstallationId() {
        XCTAssertNotNil(DeviceInfo.fixture().subscribable)
        XCTAssertNil(DeviceInfo.fixture(installationId: "").subscribable)
    }
}
