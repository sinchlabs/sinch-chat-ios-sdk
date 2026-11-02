import XCTest
import UserNotifications
@testable import SinchPushSDK

/// A stand-in for the chat addressee: suppresses a Sinch payload while it claims it.
private final class AddresseeStub: PushNotificationAddressee {
    let id: PushNotificationAddresseeName = .chat
    var claims = true

    func handleNotification(payload: [AnyHashable: Any]) -> IsHandled { claims }
    func handleWillPresentNotification(_ payload: [AnyHashable: Any]) -> UNNotificationPresentationOptions? {
        claims ? [.badge, .banner, .list] : nil
    }
}

/// APNs `willPresent` dedupe, `handleNotification` marking, and socket notification handling.
@MainActor
final class PushRoutingTests: XCTestCase {

    private var rig: RelayTestHarness!
    private var handler: RoutingHandlerStub!
    private var inApp: InAppControllerStub!
    private var push: DefaultSinchPush!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness(owner: "app-1|jwt-project|user-1")
        handler = RoutingHandlerStub()
        inApp = InAppControllerStub()
        push = DefaultSinchPush(pushNotificationHandler: handler, inAppPresenter: inApp, socketManager: rig.manager, relaySettings: rig.settings)
    }

    private func apns(_ id: String? = "m-1", owner: String? = "sinch") -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = ["aps": ["alert": "Hi"]]
        if let owner { info["owner"] = owner }
        if let id { info["sinch.push.message_id"] = id }
        return info
    }

    private func socketInfo(_ id: String = "m-1", extra: [AnyHashable: Any] = ["owner": "sinch", "topic_id": "t"]) -> [AnyHashable: Any] {
        var info = extra
        info["messageId"] = id
        info["sinchMessageId"] = "sinch-\(id)"
        info["source"] = "socket"
        return info
    }

    // MARK: - willPresent, APNs

    func testAnUnseenApnsPushIsMarkedSeenAndKeepsTodaysBehaviour() {
        let options = push.handleWillPresent(userInfo: apns(), requestIdentifier: "collapse", hasSound: true)

        XCTAssertEqual(options, [.badge, .banner, .list])
        XCTAssertEqual(handler.willPresentPayloads.count, 1)
        XCTAssertTrue(rig.registry.contains("m-1"))
    }

    func testASeenApnsPushPresentsNothing() {
        rig.registry.markSeen("m-1")

        let options = push.handleWillPresent(userInfo: apns(), requestIdentifier: "collapse", hasSound: true)

        XCTAssertEqual(options, [])
        XCTAssertTrue(handler.willPresentPayloads.isEmpty, "handled: the chat addressees are not consulted")
    }

    func testTheApnsPathDoesNotSuppressItsOwnMark() {
        // A repeated willPresent for the same push (the APNs path marked it first) is not "another channel".
        XCTAssertEqual(push.handleWillPresent(userInfo: apns(), requestIdentifier: "x", hasSound: true), [.badge, .banner, .list])
        XCTAssertEqual(push.handleWillPresent(userInfo: apns(), requestIdentifier: "x", hasSound: true), [.badge, .banner, .list])
    }

    func testTheRequestIdentifierIsTheKeyWhenASinchPayloadHasNoMessageId() {
        var info = apns(nil)
        info["sinch.push.subscriber_id"] = "s-1"
        XCTAssertEqual(push.handleWillPresent(userInfo: info, requestIdentifier: "collapse-1", hasSound: true), [.badge, .banner, .list])
        XCTAssertTrue(rig.registry.contains("collapse-1"))

        rig.registry.markSeen("collapse-2")
        XCTAssertEqual(push.handleWillPresent(userInfo: info, requestIdentifier: "collapse-2", hasSound: true), [])
    }

    func testTheRequestIdentifierIsNotAKeyForAnOwnerOnlyPayloadOrAUuid() {
        XCTAssertEqual(push.handleWillPresent(userInfo: apns(nil), requestIdentifier: "collapse-1", hasSound: true), [.badge, .banner, .list])
        XCTAssertFalse(rig.registry.contains("collapse-1"))
        var info = apns(nil)
        info["sinch.push.subscriber_id"] = "s-1"
        _ = push.handleWillPresent(userInfo: info, requestIdentifier: "6F9619FF-8B86-D011-B42D-00C04FC964FF", hasSound: true)
        XCTAssertEqual(rig.registry.snapshot, [])
    }

    func testTheMessageIdInThePayloadWinsOverTheRequestIdentifier() {
        _ = push.handleWillPresent(userInfo: apns("m-7"), requestIdentifier: "collapse", hasSound: true)
        XCTAssertTrue(rig.registry.contains("m-7"))
        XCTAssertFalse(rig.registry.contains("collapse"))
    }

    func testANotificationThatIsNotSinchIsNeverDeduped() {
        handler.willPresentResult = nil
        let info: [AnyHashable: Any] = ["aps": ["alert": "Hi"]]
        XCTAssertNil(push.handleWillPresent(userInfo: info, requestIdentifier: "daily-reminder", hasSound: true))
        XCTAssertNil(push.handleWillPresent(userInfo: info, requestIdentifier: "daily-reminder", hasSound: true),
                     "a host's own repeated identifier must not be suppressed")
        XCTAssertFalse(rig.registry.contains("daily-reminder"))
    }

    func testASinchPushWithoutAnyIdIsNotDeduped() {
        XCTAssertEqual(push.handleWillPresent(userInfo: apns(nil), requestIdentifier: "", hasSound: true), [.badge, .banner, .list])
        XCTAssertEqual(push.handleWillPresent(userInfo: apns(nil), requestIdentifier: "", hasSound: true), [.badge, .banner, .list])
        XCTAssertEqual(rig.registry.snapshot.count, 0)
    }

    // MARK: - willPresent, relay notifications

    func testASocketNotificationIsNotDedupedEvenThoughTheSocketMarkedItSeen() {
        rig.registry.markSeen("m-1")

        let options = push.handleWillPresent(userInfo: socketInfo(), requestIdentifier: "m-1", hasSound: true)

        XCTAssertEqual(options, [.badge, .banner, .list], "routed through the addressees like an APNs push")
        XCTAssertEqual(handler.willPresentPayloads.count, 1)
    }

    func testASocketNotificationNobodyClaimsGetsThePresentersDefault() {
        handler.willPresentResult = nil
        XCTAssertEqual(push.handleWillPresent(userInfo: socketInfo(extra: [:]), requestIdentifier: "m-1", hasSound: true),
                       [.banner, .list, .sound])
    }

    func testASilentSocketNotificationIsOnlyListed() {
        handler.willPresentResult = nil
        XCTAssertEqual(push.handleWillPresent(userInfo: socketInfo(extra: [:]), requestIdentifier: "m-1", hasSound: false),
                       [.list])
    }

    func testAnAddresseeCanSuppressASocketNotification() {
        handler.willPresentResult = []
        XCTAssertEqual(push.handleWillPresent(userInfo: socketInfo(), requestIdentifier: "m-1", hasSound: true), [])
    }

    func testTheAddresseeSeesTheRelayMetadata() {
        // The real handler chain: a registered addressee decides before the default presentation does.
        let defaults = UserDefaults(suiteName: "sinch.tests.routing.\(UUID().uuidString)")!
        let real = DefaultPushNotificationHandler(userDefaults: defaults)
        let addressee = AddresseeStub()
        real.registerAddressee(addressee)
        let routed = DefaultSinchPush(pushNotificationHandler: real, inAppPresenter: inApp, socketManager: rig.manager, relaySettings: rig.settings)

        XCTAssertEqual(routed.handleWillPresent(userInfo: socketInfo(extra: ["owner": "sinch"]), requestIdentifier: "m-1", hasSound: true), [.badge, .banner, .list])
        addressee.claims = false
        let released = routed.handleWillPresent(userInfo: socketInfo(extra: ["owner": "sinch"]), requestIdentifier: "m-1", hasSound: true)
        XCTAssertEqual(released, [.banner, .list, .sound], "the socket presenter decides when no addressee claims it")
    }

    // MARK: - handleNotification

    func testHandleNotificationMarksTheMessageSeenAndHandlesIt() {
        XCTAssertTrue(push.handleNotification(apns("m-2")))
        XCTAssertTrue(rig.registry.contains("m-2"))
        XCTAssertEqual(handler.handledPayloads.count, 1)

        XCTAssertTrue(push.handleNotification(apns("m-2")), "a second delivery of the same APNs payload is still handled")
        XCTAssertEqual(handler.handledPayloads.count, 2)
    }

    func testHandleNotificationUsesThePayloadKeyOnly() {
        _ = push.handleNotification(apns(nil))
        XCTAssertEqual(rig.registry.snapshot.count, 0)
    }

    func testAnInAppPayloadIsShownAndMarkedSeen() {
        inApp.shows = true
        XCTAssertTrue(push.handleNotification(apns("m-3")))
        XCTAssertTrue(rig.registry.contains("m-3"))
        XCTAssertTrue(handler.handledPayloads.isEmpty)
    }

    func testHandleNotificationIgnoresNotificationsThatAreNotSinch() {
        handler.handleResult = false
        XCTAssertFalse(push.handleNotification(["aps": ["alert": "x"]]))
        XCTAssertEqual(rig.registry.snapshot.count, 0)
    }

    // MARK: - Cross-channel dedupe only suppresses copies of the other channel

    func testDidReceiveBeforeWillPresentPresentsBoth() {
        // Foreground content-available + alert push, iOS calls didReceiveRemoteNotification first: it must not hide
        // the banner decision of willPresent.
        inApp.shows = true
        XCTAssertTrue(push.handleNotification(apns("m-1")))
        XCTAssertEqual(inApp.payloads.count, 1, "the in-app message is shown")

        XCTAssertEqual(push.handleWillPresent(userInfo: apns("m-1"), requestIdentifier: "c", hasSound: true),
                       [.badge, .banner, .list], "willPresent after the APNs path marked it still presents")
    }

    func testWillPresentBeforeDidReceiveStillShowsTheInAppMessage() {
        inApp.shows = true
        XCTAssertEqual(push.handleWillPresent(userInfo: apns("m-1"), requestIdentifier: "c", hasSound: true),
                       [.badge, .banner, .list])

        XCTAssertTrue(push.handleNotification(apns("m-1")))
        XCTAssertEqual(inApp.payloads.count, 1, "willPresent marked it, the in-app message is shown anyway")
    }

    func testASocketMessageIsNotShownAgainWhenItsApnsCopyReachesDidReceive() {
        rig.registry.markSeen("m-1")
        inApp.shows = true

        XCTAssertTrue(push.handleNotification(apns("m-1")), "handled")
        XCTAssertTrue(inApp.payloads.isEmpty, "not shown a second time")
        XCTAssertTrue(handler.handledPayloads.isEmpty, "no addressee either")
    }

    func testASocketMessageIsNotPresentedAgainWhenItsApnsCopyReachesWillPresent() {
        rig.registry.markSeen("m-1")
        XCTAssertEqual(push.handleWillPresent(userInfo: apns("m-1"), requestIdentifier: "c", hasSound: true), [])
    }

    func testAnIdFromAPreviousProcessIsACopyOnBothEntryPoints() {
        // Only the persisted registry remembers it: the APNs path of *this* process never marked it.
        let store = FakeSocketStateStore(seen: ["m-old"])
        let relaunched = RelayTestHarness(store: store)
        let relaunchedPush = DefaultSinchPush(pushNotificationHandler: handler, inAppPresenter: inApp,
                                              socketManager: relaunched.manager, relaySettings: relaunched.settings)
        inApp.shows = true

        XCTAssertEqual(relaunchedPush.handleWillPresent(userInfo: apns("m-old"), requestIdentifier: "c", hasSound: true), [])
        XCTAssertTrue(relaunchedPush.handleNotification(apns("m-old")))
        XCTAssertTrue(inApp.payloads.isEmpty)
    }

    func testATapIsNeverSuppressedByDedupe() {
        rig.registry.markSeen("m-1")
        let handled = push.handleResponse(userInfo: apns("m-1"), requestIdentifier: "c",
                                          actionIdentifier: UNNotificationDefaultActionIdentifier)
        XCTAssertTrue(handled)
        XCTAssertEqual(handler.handledPayloads.count, 1, "opens the chat although the socket delivered it")
    }

    // MARK: - Socket-sourced means source and the socket category

    func testASocketNotificationNeedsTheSocketCategory() {
        handler.willPresentResult = nil
        let socketCategory = SocketNotificationPresenter.category

        XCTAssertEqual(push.handleWillPresent(userInfo: socketInfo(extra: [:]), requestIdentifier: "m-1", hasSound: true,
                                              categoryIdentifier: socketCategory),
                       [.banner, .list, .sound])

        rig.registry.markSeen("m-1")
        XCTAssertEqual(push.handleWillPresent(userInfo: socketInfo("m-1", extra: ["sinch.push.message_id": "m-1"]),
                                              requestIdentifier: "m-1", hasSound: true, categoryIdentifier: ""),
                       [])
    }

    func testADismissOfAnotherCategoryIsNotASocketDismiss() {
        let handled = push.handleResponse(userInfo: socketInfo("m-9"), requestIdentifier: "m-9",
                                          actionIdentifier: UNNotificationDismissActionIdentifier,
                                          categoryIdentifier: "host.category")
        XCTAssertEqual(rig.store.loadOutbox().count, 0, "no DISMISSED report")
        XCTAssertTrue(handled)
        XCTAssertEqual(handler.handledPayloads.count, 1, "went the APNs way")
    }

    // MARK: - A silent relay notification stays silent

    func testASilentSocketNotificationIsNotUpgradedByTheAddressee() {
        handler.willPresentResult = [.badge, SocketPresentation.legacyAlert]
        XCTAssertEqual(push.handleWillPresent(userInfo: socketInfo(), requestIdentifier: "m-1", hasSound: false),
                       [.badge, .list], "no banner, no sound")
        XCTAssertEqual(push.handleWillPresent(userInfo: socketInfo(), requestIdentifier: "m-1", hasSound: true),
                       [.badge, SocketPresentation.legacyAlert], "an alerting one keeps the addressee's answer")
    }

    func testSilencingKeepsOnlyListAndBadge() {
        XCTAssertEqual(SocketPresentation.silenced([.badge, SocketPresentation.legacyAlert]), [.badge, .list])
        XCTAssertEqual(SocketPresentation.silenced([.banner, .list, .sound, .badge]), [.list, .badge])
        XCTAssertEqual(SocketPresentation.silenced([.sound]), [])
        XCTAssertEqual(SocketPresentation.silenced([]), [])
    }

    // MARK: - Responses

    func testDismissingASocketNotificationReportsDismissedAndOpensNothing() async {
        rig.start()
        await rig.handshake()

        let handled = push.handleResponse(userInfo: socketInfo("m-9"), requestIdentifier: "m-9",
                                          actionIdentifier: UNNotificationDismissActionIdentifier)

        XCTAssertTrue(handled)
        XCTAssertTrue(handler.handledPayloads.isEmpty, "a swipe must not open the chat")
        XCTAssertEqual(rig.factory.current?.reports.map(\.status), [.dismissed])
        XCTAssertEqual(rig.factory.current?.reports.first?.messageID, "m-9")
    }

    func testADismissWhileTheSocketIsClosedIsQueued() {
        _ = push.handleResponse(userInfo: socketInfo("m-9"), requestIdentifier: "m-9",
                                actionIdentifier: UNNotificationDismissActionIdentifier)
        XCTAssertEqual(rig.store.loadOutbox().map(\.messageId), ["m-9"])
        XCTAssertEqual(rig.store.loadOutbox().map(\.status), [.dismissed])
    }

    func testTheRequestIdentifierIdentifiesTheMessageWhenUserInfoLacksIt() {
        var info = socketInfo("ignored")
        info["messageId"] = nil
        _ = push.handleResponse(userInfo: info, requestIdentifier: "m-5", actionIdentifier: UNNotificationDismissActionIdentifier)
        XCTAssertEqual(rig.store.loadOutbox().map(\.messageId), ["m-5"])
    }

    func testTappingASocketNotificationOpensTheChat() {
        let handled = push.handleResponse(userInfo: socketInfo(), requestIdentifier: "m-1",
                                          actionIdentifier: UNNotificationDefaultActionIdentifier)
        XCTAssertTrue(handled)
        XCTAssertEqual(handler.handledPayloads.count, 1)
        XCTAssertTrue(rig.store.loadOutbox().isEmpty)
    }

    func testTappingAnApnsNotificationMarksItSeenAndOpensTheChat() {
        let handled = push.handleResponse(userInfo: apns("m-4"), requestIdentifier: "collapse",
                                          actionIdentifier: UNNotificationDefaultActionIdentifier)
        XCTAssertTrue(handled)
        XCTAssertTrue(rig.registry.contains("m-4"))
        XCTAssertEqual(handler.handledPayloads.count, 1)
    }

    func testTheReturnValueOfTheHandlerIsKept() {
        handler.handleResult = false
        XCTAssertFalse(push.handleResponse(userInfo: ["aps": ["alert": "x"]], requestIdentifier: "x",
                                           actionIdentifier: UNNotificationDefaultActionIdentifier))
    }

    // MARK: - Public API surface

    func testThePublicApiIsBackedByTheManager() async {
        XCTAssertEqual(push.socketState, rig.manager.state)
        XCTAssertEqual(push.installationId, "install-1")

        let states = PublisherCollector(push.socketStatePublisher)
        let messages = PublisherCollector(push.socketMessagePublisher)
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1")
        await rig.flush()
        push.reportStatus(messageId: "m-1", status: .displayed)

        XCTAssertEqual(states.values.last?.status, .connected)
        XCTAssertEqual(messages.values.map(\.id), ["m-1"])
        XCTAssertTrue(rig.factory.current!.reports.contains { $0.messageID == "m-1" && $0.status == .displayed })
    }
}
