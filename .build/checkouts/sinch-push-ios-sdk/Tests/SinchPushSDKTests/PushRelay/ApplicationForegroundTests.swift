import UIKit
import XCTest
@testable import SinchPushSDK

/// `UIApplication.applicationState` as the relay sees it: `.inactive` (a launch from a notification) is foreground.
final class ApplicationForegroundTests: XCTestCase {

    func testActiveIsForeground() {
        XCTAssertTrue(PushSocketManager.Dependencies.isForeground(.active))
    }

    func testInactiveIsForeground() {
        XCTAssertTrue(PushSocketManager.Dependencies.isForeground(.inactive))
    }

    func testBackgroundIsNotForeground() {
        XCTAssertFalse(PushSocketManager.Dependencies.isForeground(.background))
    }
}
