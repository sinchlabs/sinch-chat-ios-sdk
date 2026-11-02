//  UIApplicationSocketLifecycleTests.swift — the UIKit notification wiring.
//  The observers use `queue: .main`, so delivery is awaited rather than assumed synchronous.

import UIKit
import XCTest

@testable import SinchPushSDK

@MainActor
final class UIApplicationSocketLifecycleTests: XCTestCase {

    func testDidEnterBackgroundSuspendsTheClientAndForegroundResumesIt() async {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        let lifecycle = UIApplicationSocketLifecycle(client: harness.client)
        lifecycle.startObserving()
        defer { lifecycle.stopObserving() }

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await waitUntil { harness.transport.closeCalls.last?.code == 1000 }
        XCTAssertEqual(harness.recorder.current?.status, .idle)
        let socketsWhileBackgrounded = harness.socketCount

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await waitUntil { harness.socketCount == socketsWhileBackgrounded + 1 }
        XCTAssertEqual(harness.recorder.current?.status, .connecting)
    }

    func testAStoppedObserverNoLongerDrivesTheClient() async {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        let lifecycle = UIApplicationSocketLifecycle(client: harness.client)
        lifecycle.startObserving()
        lifecycle.stopObserving()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await drainMainQueue()

        XCTAssertTrue(harness.transport.closeCalls.isEmpty)
        XCTAssertEqual(harness.recorder.current?.status, .connected)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
