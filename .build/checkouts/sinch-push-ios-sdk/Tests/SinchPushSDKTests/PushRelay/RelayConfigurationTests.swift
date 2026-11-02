import XCTest
@testable import SinchPushSDK

/// Region / AppConfig Codable back-compat and relay URL resolution.
final class RelayConfigurationTests: XCTestCase {

    // MARK: - Region Codable back-compat

    /// JSON as written by the SDK before `relayURL` existed (and persisted in `AuthModel`s in the Keychain).
    func testRegionDecodesJSONEncodedBeforeRelayURLExisted() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(Region.self, from: Data(#"{"EU1":{}}"#.utf8)), .EU1)
        XCTAssertEqual(try decoder.decode(Region.self, from: Data(#"{"US1":{}}"#.utf8)), .US1)

        let full = try decoder.decode(
            Region.self,
            from: Data(#"{"custom":{"host":"h","isSecure":false,"port":8080,"pushAPIHost":"p"}}"#.utf8))
        XCTAssertEqual(full, .custom(host: "h", pushAPIHost: "p", port: 8080, isSecure: false, relayURL: nil))

        let minimal = try decoder.decode(Region.self, from: Data(#"{"custom":{"host":"h","pushAPIHost":"p"}}"#.utf8))
        XCTAssertEqual(minimal, .custom(host: "h", pushAPIHost: "p", port: nil, isSecure: nil))
    }

    func testRegionWithoutRelayURLEncodesToTheOldShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(Region.custom(host: "h", pushAPIHost: "p", port: 8080, isSecure: false))
        XCTAssertEqual(String(data: json, encoding: .utf8), #"{"custom":{"host":"h","isSecure":false,"port":8080,"pushAPIHost":"p"}}"#)
    }

    func testRegionRoundTripsRelayURL() throws {
        let region = Region.custom(host: "h", pushAPIHost: "p", port: nil, isSecure: true,
                                   relayURL: URL(string: "wss://relay.example.com/ws"))
        let decoded = try JSONDecoder().decode(Region.self, from: JSONEncoder().encode(region))
        XCTAssertEqual(decoded, region)
    }

    func testAuthModelPersistedBeforeRelayURLStillDecodes() throws {
        let json = #"""
        {"accessToken":"t","sinchIdentity":{"anonymous":{}},"clientID":"c","projectID":"p","configID":"cfg",
         "region":{"custom":{"host":"h","isSecure":true,"pushAPIHost":"p"}}}
        """#
        let model = try JSONDecoder().decode(AuthModel.self, from: Data(json.utf8))
        XCTAssertEqual(model.region, .custom(host: "h", pushAPIHost: "p", port: nil, isSecure: true))
    }

    // MARK: - AppConfig

    func testAppConfigDecodesWithoutRelayAsEnabled() throws {
        let original = SinchSDKConfig.AppConfig(clientID: "c", projectID: "p", configID: "cfg", region: .EU1,
                                                locale: Locale(identifier: "en_US"), relay: .disabled)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        XCTAssertEqual(object["relay"] as? String, "disabled")

        object["relay"] = nil
        let decoded = try JSONDecoder().decode(
            SinchSDKConfig.AppConfig.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.relay, .enabled)
        XCTAssertEqual(decoded.clientID, "c")
        XCTAssertEqual(decoded.region, .EU1)
    }

    func testAppConfigRelayRoundTrips() throws {
        let original = SinchSDKConfig.AppConfig(clientID: "c", projectID: "p", configID: "cfg", region: .US1,
                                                relay: .disabled)
        let decoded = try JSONDecoder().decode(SinchSDKConfig.AppConfig.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.relay, .disabled)
    }

    func testAppConfigRelayDefaultsToEnabled() {
        let config = SinchSDKConfig.AppConfig(clientID: "c", projectID: "p", configID: "cfg", region: .EU1)
        XCTAssertEqual(config.relay, .enabled)
        XCTAssertFalse(config.allowInsecureRelay)
    }

    func testAppConfigDecodesWithoutAllowInsecureRelayAsFalse() throws {
        let original = SinchSDKConfig.AppConfig(clientID: "c", projectID: "p", configID: "cfg", region: .EU1,
                                                allowInsecureRelay: true)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        XCTAssertEqual(object["allowInsecureRelay"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(SinchSDKConfig.AppConfig.self, from: JSONEncoder().encode(original)),
                       original)

        object["allowInsecureRelay"] = nil
        let decoded = try JSONDecoder().decode(
            SinchSDKConfig.AppConfig.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.allowInsecureRelay)
    }

    // MARK: - Resolution

    private func custom(isSecure: Bool?, relay: String?) -> Region {
        custom(pushAPIHost: "p", isSecure: isSecure, relay: relay)
    }

    private func custom(pushAPIHost: String, isSecure: Bool?, relay: String?) -> Region {
        .custom(host: "h", pushAPIHost: pushAPIHost, port: nil, isSecure: isSecure,
                relayURL: relay.flatMap(URL.init(string:)))
    }

    private func assertDisabled(_ resolution: RelayResolution, containing text: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard case .disabled(let reason) = resolution else {
            return XCTFail("expected disabled, got \(resolution)", file: file, line: line)
        }
        XCTAssertTrue(reason.contains(text), "reason \"\(reason)\" lacks \"\(text)\"", file: file, line: line)
    }

    private func assertEnabled(_ resolution: RelayResolution, _ expected: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(resolution, .enabled(URL(string: expected)!),
                       "expected \(expected), got \(resolution)", file: file, line: line)
    }

    func testBuiltInRegionsUseTheirProductionRelay() {
        assertEnabled(RelayEndpoint.resolve(region: .EU1, option: .enabled),
                      "wss://relay.sinch-push.prod.sinch.com/ws")
        assertEnabled(RelayEndpoint.resolve(region: .US1, option: .enabled),
                      "wss://relay.sinch-push.us1.prod.sinch.com/ws")
    }

    func testCustomRegionDerivesTheStagingRelayFromItsPushHost() {
        for pushHost in ["grpc.sinch-push.staging.sinch.com", "grpc.sinch-push.eu1tst.staging.sinch.com"] {
            assertEnabled(RelayEndpoint.resolve(region: custom(pushAPIHost: pushHost, isSecure: true, relay: nil),
                                                option: .enabled),
                          "wss://relay.sinch-push.eu1tst.staging.sinch.com/ws")
        }
    }

    func testCustomRegionDerivesTheProductionRelayFromItsPushHost() {
        assertEnabled(RelayEndpoint.resolve(region: custom(pushAPIHost: "grpc.sinch-push.prod.sinch.com",
                                                           isSecure: true, relay: nil), option: .enabled),
                      "wss://relay.sinch-push.prod.sinch.com/ws")
        assertEnabled(RelayEndpoint.resolve(region: custom(pushAPIHost: "grpc.sinch-push.us1.prod.sinch.com",
                                                           isSecure: true, relay: nil), option: .enabled),
                      "wss://relay.sinch-push.us1.prod.sinch.com/ws")
    }

    func testThePushHostIsMatchedCaseInsensitively() {
        assertEnabled(RelayEndpoint.resolve(region: custom(pushAPIHost: "GRPC.SINCH-PUSH.EU1TST.STAGING.SINCH.COM",
                                                           isSecure: true, relay: nil), option: .enabled),
                      "wss://relay.sinch-push.eu1tst.staging.sinch.com/ws")
    }

    func testCustomRegionWithAnUnknownPushHostIsDisabled() {
        assertDisabled(RelayEndpoint.resolve(region: custom(pushAPIHost: "grpc.sinch-push.example.com",
                                                            isSecure: true, relay: nil), option: .enabled),
                       containing: "no relay host for push host grpc.sinch-push.example.com")
    }

    func testAnExplicitRelayURLWinsOverTheDerivedOne() {
        let region = custom(pushAPIHost: "grpc.sinch-push.staging.sinch.com", isSecure: true,
                            relay: "wss://relay.example.com/ws")
        assertEnabled(RelayEndpoint.resolve(region: region, option: .enabled),
                      "wss://relay.example.com/ws")
    }

    func testKillSwitchWinsOverAValidURL() {
        let region = custom(isSecure: true, relay: "wss://relay.example.com/ws")
        assertDisabled(RelayEndpoint.resolve(region: region, option: .disabled), containing: "relay: .disabled")
    }

    func testCustomWithoutURLIsDisabledWhenThePushHostIsUnknown() {
        assertDisabled(RelayEndpoint.resolve(region: custom(isSecure: true, relay: nil), option: .enabled),
                       containing: "no relay host for push host p")
    }

    func testWssIsAlwaysAllowed() {
        for isSecure in [true, false, nil] as [Bool?] {
            let region = custom(isSecure: isSecure, relay: "wss://relay.example.com/ws")
            XCTAssertEqual(RelayEndpoint.resolve(region: region, option: .enabled),
                           .enabled(URL(string: "wss://relay.example.com/ws")!), "isSecure: \(String(describing: isSecure))")
        }
    }

    func testWsNeedsAllowInsecureRelayWhateverIsSecureSays() {
        let url = URL(string: "ws://127.0.0.1:8080/ws")!
        for isSecure in [true, false, nil] as [Bool?] {
            let region = custom(isSecure: isSecure, relay: url.absoluteString)
            assertDisabled(RelayEndpoint.resolve(region: region, option: .enabled), containing: "allowInsecureRelay")
            assertDisabled(RelayEndpoint.resolve(region: region, option: .enabled, allowInsecure: false),
                           containing: "allowInsecureRelay")
            XCTAssertEqual(RelayEndpoint.resolve(region: region, option: .enabled, allowInsecure: true), .enabled(url),
                           "isSecure: \(String(describing: isSecure))")
        }
    }

    func testAllowInsecureRelayDoesNotChangeWss() {
        let region = custom(isSecure: true, relay: "wss://relay.example.com/ws")
        XCTAssertEqual(RelayEndpoint.resolve(region: region, option: .enabled, allowInsecure: true),
                       .enabled(URL(string: "wss://relay.example.com/ws")!))
    }

    func testSchemeIsMatchedCaseInsensitively() {
        let region = custom(isSecure: true, relay: "WSS://relay.example.com/ws")
        XCTAssertEqual(RelayEndpoint.resolve(region: region, option: .enabled),
                       .enabled(URL(string: "WSS://relay.example.com/ws")!))
    }

    func testOtherSchemesAndHostlessURLsAreDisabled() {
        for bad in ["https://relay.example.com/ws", "http://relay.example.com", "relay.example.com", "wss:///ws"] {
            let resolution = RelayEndpoint.resolve(region: custom(isSecure: false, relay: bad), option: .enabled,
                                                   allowInsecure: true)
            guard case .disabled = resolution else {
                XCTFail("\(bad) must be disabled, got \(resolution)")
                continue
            }
        }
    }

    // MARK: - Token cache is independent of the relay URL

    func testRelayURLIsNotPartOfTheBackendIdentity() {
        let withRelay = custom(isSecure: true, relay: "wss://relay.example.com/ws")
        let without = custom(isSecure: true, relay: nil)
        XCTAssertNotEqual(withRelay, without)
        XCTAssertEqual(withRelay.withoutRelayURL, without.withoutRelayURL)
        XCTAssertEqual(Region.EU1.withoutRelayURL, .EU1)
    }

    // MARK: - JWTDecoder

    func testJWTDecoderThrowsInsteadOfTrappingOnAMalformedToken() {
        XCTAssertThrowsError(try JWTDecoder.decode(jwtToken: "not-a-jwt"))
        XCTAssertThrowsError(try JWTDecoder.decode(jwtToken: ""))
    }
}
