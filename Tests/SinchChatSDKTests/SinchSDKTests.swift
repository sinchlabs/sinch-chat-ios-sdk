import XCTest
@testable import SinchSDK

final class SinchSDKTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(sdk_spm_cocoapods().text, "Hello, World!")
    }
}
