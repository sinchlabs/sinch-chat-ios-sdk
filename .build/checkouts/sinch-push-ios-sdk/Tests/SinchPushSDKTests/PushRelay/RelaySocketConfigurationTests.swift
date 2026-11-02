import XCTest
@testable import SinchPushSDK

/// What `SocketConfiguration.relay` derives from the access token, and why it refuses.
final class RelaySocketConfigurationTests: XCTestCase {

    private func relay(token: String) -> Result<SocketConfiguration, RelayConfigurationError> {
        let auth = AuthModel(accessToken: token, sinchIdentity: .anonymous, clientID: "c", projectID: "p",
                             configID: "cfg", region: relayRegion())
        return SocketConfiguration.relay(url: URL(string: "wss://relay.example.com/ws")!, auth: auth, config: makeAppConfig())
    }

    private func relay(claims: [String: Any]) -> Result<SocketConfiguration, RelayConfigurationError> {
        relay(token: makeJWT(claims))
    }

    private func assertFailure(_ result: Result<SocketConfiguration, RelayConfigurationError>,
                               _ expected: RelayConfigurationError, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = result else { return XCTFail("expected \(expected)", file: file, line: line) }
        XCTAssertEqual(error, expected, file: file, line: line)
    }

    func testAValidTokenYieldsTheClaimsOfTheToken() throws {
        let configuration = try relay(claims: ["uuid": "u", "appId": "a", "projectId": "p"]).get()
        XCTAssertEqual(configuration.userID, "u")
        XCTAssertEqual(configuration.appID, "a")
        XCTAssertEqual(configuration.projectID, "p")
    }

    func testATokenWithoutUserIDIsRefused() {
        assertFailure(relay(claims: ["appId": "a"]), .missingUserID)
    }

    func testAnEmptyUserIDIsRefused() {
        assertFailure(relay(claims: ["uuid": "", "appId": "a"]), .missingUserID)
    }

    func testAWrongTypedUserIDIsRefused() {
        assertFailure(relay(claims: ["uuid": 7, "appId": "a"]), .missingUserID)
    }

    func testAnEmptyTokenIsRefusedAsMissingUserID() {
        assertFailure(relay(token: ""), .missingUserID)
    }

    func testMalformedTokensAreRefusedAsMissingUserID() {
        assertFailure(relay(token: "not-a-jwt"), .missingUserID)
        assertFailure(relay(token: "a.!!!.c"), .missingUserID)
        assertFailure(relay(token: "a.\(Data("not json".utf8).base64EncodedString()).c"), .missingUserID)
        assertFailure(relay(token: "a.\(Data("[1,2]".utf8).base64EncodedString()).c"), .missingUserID)
    }

    func testAUserIDWithoutAppIDIsRefusedAsMissingAppID() {
        assertFailure(relay(claims: ["uuid": "u"]), .missingAppID)
    }
}
