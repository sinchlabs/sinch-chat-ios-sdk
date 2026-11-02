//  The 128-byte cap on `os_version`, `bundle_id` and `sdk_version`: the relay rejects a
//  longer `Hello`, so the clamp is by bytes and never splits a character.

import Foundation
import XCTest

@testable import SinchPushSDK

final class DeviceInfoClampTests: XCTestCase {

    // MARK: - The helper

    func testAValueInsideTheCapIsReturnedUnchanged() throws {
        // `==` on String compares by canonical equivalence, so the byte count is asserted too.
        let bundleId = "com.sinch.example"
        let clamped = DeviceInfo.clampedUTF8(bundleId)
        XCTAssertEqual(clamped, bundleId)
        XCTAssertEqual(clamped.utf8.count, bundleId.utf8.count)
        XCTAssertEqual(bundleId.utf8.count, 17)
    }

    func testALongAsciiValueIsCutToExactlyTheCap() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(long.utf8.count, 200)
        let clamped = DeviceInfo.clampedUTF8(long)
        XCTAssertEqual(clamped.utf8.count, 128)
        XCTAssertEqual(clamped, String(repeating: "a", count: 128))
    }

    func testAMultiByteValueIsCutToTheCapWithoutBreakingACharacter() {
        // "ż" is two UTF-8 bytes, so a 128-Character budget would put 256 bytes on the wire.
        let long = String(repeating: "ż", count: 100)
        XCTAssertEqual(long.utf8.count, 200)
        let clamped = DeviceInfo.clampedUTF8(long)
        XCTAssertLessThanOrEqual(clamped.utf8.count, DeviceInfo.maxDeviceInfoValueBytes)
        XCTAssertEqual(clamped.utf8.count, 128)
        XCTAssertEqual(clamped, String(repeating: "ż", count: 64))
        // `String(decoding:)` substitutes U+FFFD for malformed input, so this catches a cut inside a scalar.
        let roundTripped = String(decoding: clamped.utf8, as: UTF8.self)
        XCTAssertEqual(roundTripped, clamped)
        XCTAssertFalse(roundTripped.unicodeScalars.contains("\u{FFFD}"))
    }

    func testEmojiSequenceAreKeptWholeRatherThanSplit() {
        // "👩‍💻" is one `Character` and 11 bytes: 11 of the 20 fit (121 bytes).
        let emojis = String(repeating: "\u{1F469}\u{200D}\u{1F4BB}", count: 20)
        XCTAssertEqual(emojis.count, 20)
        XCTAssertGreaterThan(emojis.utf8.count, DeviceInfo.maxDeviceInfoValueBytes)
        let clamped = DeviceInfo.clampedUTF8(emojis)
        XCTAssertEqual(clamped.utf8.count, 121)
        XCTAssertEqual(clamped.count, 11)
        XCTAssertEqual(clamped, String(repeating: "\u{1F469}\u{200D}\u{1F4BB}", count: 11))
    }

    func testAGraphemeClusterWiderThanTheCapYieldsNothingRatherThanHalf() {
        // One `Character` of 404 bytes: no prefix fits, and empty reads as "absent" to the relay.
        let wide = "\u{1F469}" + String(repeating: "\u{0301}", count: 200)
        XCTAssertEqual(wide.count, 1)
        XCTAssertEqual(wide.utf8.count, 404)
        XCTAssertEqual(DeviceInfo.clampedUTF8(wide), "")
    }

    func testTheCapIsTheContracts128Bytes() {
        XCTAssertEqual(DeviceInfo.maxDeviceInfoValueBytes, 128)
        let exactly = String(repeating: "b", count: DeviceInfo.maxDeviceInfoValueBytes)
        XCTAssertEqual(DeviceInfo.clampedUTF8(exactly), exactly)
        let oneOver = String(repeating: "b", count: DeviceInfo.maxDeviceInfoValueBytes + 1)
        XCTAssertEqual(DeviceInfo.clampedUTF8(oneOver).utf8.count, 128)
    }

    func testTheHelperLeavesTheEmptyStringAlone() {
        XCTAssertEqual(DeviceInfo.clampedUTF8(""), "")
    }

    // MARK: - Applied where DeviceInfo is built

    func testTheProductionProviderClampsTheThreeCappedFields() throws {
        let long = String(repeating: "z", count: 200)
        let provider = SystemDeviceInfoProvider(
            installationId: { "6f1c2a9e-3b7d-4e8a-9c21-5d4b7a0e1f23" },
            osVersion: { long },
            bundleId: { long })
        let info = provider.current(sdkVersionOverride: long)

        XCTAssertEqual(info.osVersion.utf8.count, 128)
        XCTAssertEqual(info.bundleId.utf8.count, 128)
        XCTAssertEqual(info.sdkVersion.utf8.count, 128)
        XCTAssertEqual(info.installationId, "6f1c2a9e-3b7d-4e8a-9c21-5d4b7a0e1f23")
        XCTAssertEqual(info.platform, SocketConfiguration.platform)
    }

    func testTheStaticProviderClampsTheSameWay() throws {
        let provider = StaticDeviceInfoProvider(
            installationId: "6f1c2a9e-3b7d-4e8a-9c21-5d4b7a0e1f23",
            osVersion: String(repeating: "z", count: 200),
            bundleId: String(repeating: "ż", count: 100))
        let info = provider.current(sdkVersionOverride: String(repeating: "z", count: 300))

        XCTAssertEqual(info.osVersion.utf8.count, 128)
        XCTAssertEqual(info.bundleId.utf8.count, 128)
        XCTAssertEqual(info.sdkVersion.utf8.count, 128)
        XCTAssertFalse(info.bundleId.unicodeScalars.contains("\u{FFFD}"))
        XCTAssertEqual(info.bundleId, String(repeating: "ż", count: 64))
    }

    func testNormalDeviceValuesReachDeviceInfoUntouched() throws {
        let provider = testDeviceInfo(
            installationId: "0b9c1f0e-6f3a-4b8e-9d57-2f6f6c1a7e11",
            osVersion: "17.5.1",
            bundleId: "com.example.host")
        let info = provider.current(sdkVersionOverride: nil)
        XCTAssertEqual(info.osVersion, "17.5.1")
        XCTAssertEqual(info.bundleId, "com.example.host")
        XCTAssertEqual(info.sdkVersion, SocketConfiguration.resolveSDKVersion(nil))
    }

    func testAHelloBuiltByTheClientCarriesAtMostTheCapForEveryCappedField() throws {
        let harness = makeHarness(
            deviceInfo: testDeviceInfo(
                osVersion: String(repeating: "o", count: 200),
                bundleId: String(repeating: "ż", count: 100)))
        harness.transport.openSocket()

        let hello = try XCTUnwrap(harness.hello)
        XCTAssertEqual(hello.bundleID, String(repeating: "ż", count: 64))
        XCTAssertLessThanOrEqual(hello.bundleID.utf8.count, 128)
        XCTAssertEqual(hello.osVersion.utf8.count, 128)
        XCTAssertLessThanOrEqual(hello.sdkVersion.utf8.count, 128)
    }
}
