//  The round-trip needs a Keychain entitlement, so it skips on exactly
//  `errSecMissingEntitlement` (-34018).

import XCTest

@testable import SinchPushSDK

final class KeychainAuthTokenStoreTests: XCTestCase {

    private let service = "com.sinch.chatsdk.tests.pushsocket-token"
    private var store: KeychainAuthTokenStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipIfKeychainUnavailable()
        store = KeychainAuthTokenStore(service: service, account: "auth-token", logger: SilentSocketLogger())
        store.clearToken()
    }

    override func tearDown() {
        store?.clearToken()
        store = nil
        super.tearDown()
    }

    func testAMissingTokenLoadsAsNil() {
        XCTAssertNil(store.loadToken())
    }

    func testTheTokenRoundTripsAndIsReplacedInPlace() {
        store.saveToken("first.jwt")
        XCTAssertEqual(store.loadToken(), "first.jwt")

        store.saveToken("second.jwt")
        XCTAssertEqual(store.loadToken(), "second.jwt")
    }

    func testClearingTheTokenRemovesIt() {
        store.saveToken("jwt")
        store.clearToken()
        XCTAssertNil(store.loadToken())
    }
}
