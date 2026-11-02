import Foundation
import XCTest
import CryptoKit
@testable import SinchPushSDK

/// The switch for every test that talks to a real backend.
///
/// `xcodebuild` forwards environment variables to the test runner only with the `TEST_RUNNER_` prefix, so
/// `TEST_RUNNER_SINCH_LIVE_TESTS=1` also works.
enum LiveTests {
    static var areEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SINCH_LIVE_TESTS"] == "1" || environment["TEST_RUNNER_SINCH_LIVE_TESTS"] == "1"
    }

    static func skipUnlessEnabled() throws {
        try XCTSkipUnless(areEnabled, "live tests are off (set SINCH_LIVE_TESTS=1)")
    }
}

/// The hosts of the live tests, as the demo app and the React Native SDK use them.
enum LiveHosts {

    struct Chat: Sendable {
        let name: String
        let baseURL: URL
    }

    struct Push: Sendable {
        let name: String
        let baseURL: URL
    }

    static let chatEU1 = Chat(name: "eu1", baseURL: URL(string: "https://grpc-web.sinch-chat.prod.sinch.com")!)
    static let chatUS1 = Chat(name: "us1", baseURL: URL(string: "https://grpc-web.sinch-chat.us1.prod.sinch.com")!)
    static let chatStaging = Chat(name: "staging", baseURL: URL(string: "https://grpc.sinch-chat.staging.sinch.com")!)

    static let pushEU1 = Push(name: "eu1", baseURL: URL(string: "https://grpc.sinch-push.prod.sinch.com")!)
    static let pushUS1 = Push(name: "us1", baseURL: URL(string: "https://grpc.sinch-push.us1.prod.sinch.com")!)
    static let pushStaging = Push(name: "staging", baseURL: URL(string: "https://grpc.sinch-push.staging.sinch.com")!)

    static let issueAnonymousTokenPath = ChatAuthClient.issueAnonymousTokenPath
    static let issueTokenWithSignedUuidPath = ChatAuthClient.issueTokenWithSignedUuidPath
    static let subscribePath = DefaultPushRepository.Path.subscribe
    static let unsubscribePath = DefaultPushRepository.Path.unsubscribe
    static let reportEventsPath = PushAPIDeliveryReportSender.path
}

/// Demo credentials, taken from `DemoApp/SinchChatDemo/StartView.swift`.
enum LiveDemoConfig {

    struct App: Sendable {
        let name: String
        let projectID: String
        let clientID: String
        let configID: String
        let secret: String?
    }

    /// EU1.
    static let contactProStandard = App(
        name: "contactProStandard",
        projectID: "c0e618c6-057f-4b8d-a33a-1ae51bd58ed0",
        clientID: "01KGHSNJCQ1AJNAYCQ3YFFCCKY",
        configID: "01HVNT2M8B1GEZN2NVR73H1BB4",
        secret: nil)

    /// US1.
    static let pushLab = App(
        name: "pushLab",
        projectID: "f72c669e-3182-43f5-860f-6f00c873c20e",
        clientID: "01M643H03YFHK4GY5N1YC5VFWR",
        configID: "01M63HEP6GSJ3001BC7EFBAGM8",
        secret: nil)

    /// Staging, with the demo app secret.
    static let inAppStaging = App(
        name: "inAppEnviroment",
        projectID: "e1bb4db8-c2d6-4d04-8702-fa4733854dce",
        clientID: "01K7F7DJJWH74HWBHG235ZG7RA",
        configID: "01KBYMJ3ATRY4XF2X44BM8ZP9C",
        secret: "secret")

    /// A dummy APNs device token: 64 hex characters, as APNs sends them.
    static let dummyAPNsToken = String(repeating: "a1b2c3d4", count: 8)

    /// The HMAC-SHA512 of a message, keyed with a secret, as lowercase hex: the `uuid_hash` of
    /// `IssueTokenWithSignedUuid`.
    static func hmacSHA512Hex(message: String, key: String) -> String {
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<SHA512>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return code.map { String(format: "%02x", $0) }.joined()
    }
}
