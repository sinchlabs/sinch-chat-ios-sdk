import XCTest
import GRPC
import Logging

@testable import SinchChatSDK

final class ApiClientTests: XCTestCase {

    var client: APIClient?
    
    override func tearDown() {
        super.tearDown()
        client?.closeChannel()
        client = nil
    }
    func testInititializationEU() {
        client = DefaultAPIClient(region: .EU1)

        XCTAssertNotNil(client?.getChannel(), "The channel should not be nil.")
        XCTAssertTrue(client?.isChannelStarted ?? true)
        
    }
    func testInititializationUS() {

        expectFatalError(expectedMessage: "there is no url for US region provided yet") {
            self.client = DefaultAPIClient(region: .US1)

        }
    }
    func testInititializationCustom() {

        client = DefaultAPIClient(region: .custom(host: "sdk.sinch-chat.unauth.prod.sinch.com", pushAPIHost: ""))

        XCTAssertNotNil(client?.getChannel(), "The channel should not be nil.")
        XCTAssertTrue(client?.isChannelStarted ?? true)
    }
    
    func testStartingChannelInititialization() {
        client = DefaultAPIClient(region: .EU1)
        client?.closeChannel()
        client?.startChannel()
        
        XCTAssertNotNil(client?.getChannel(), "The channel should not be nil.")
        XCTAssertTrue(client?.isChannelStarted ?? true)
        
    }
    func testCloseChannel() {
        client = DefaultAPIClient(region: .EU1)
        client?.closeChannel()

        XCTAssertFalse(client?.isChannelStarted ?? false)
    }
}
extension XCTestCase {
    func expectFatalError(expectedMessage: String, testcase: @escaping () -> Void) {
        let expectation = self.expectation(description: "expectingFatalError")
        var assertionMessage: String = ""

        triggerFatalError = { (message, _, _) in
            assertionMessage = message()
            DispatchQueue.main.async {
                expectation.fulfill()
            }
            Thread.exit()
            Swift.fatalError("will never be executed since thread exits")
        }

        Thread(block: testcase).start()

        waitForExpectations(timeout: 0.1) { _ in
            XCTAssertEqual(expectedMessage, assertionMessage)
            triggerFatalError = Swift.fatalError
        }
    }
}
