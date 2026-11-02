import Foundation

@testable import SinchPushSDK

/// The state a test collects and asserts on.
final class StateRecorder: @unchecked Sendable {
    private(set) var states: [SocketState] = []
    private(set) var messages: [SocketMessageEvent] = []
    private(set) var authRequiredCount = 0

    var statuses: [SocketStatus] { states.map(\.status) }

    var current: SocketState? { states.last }

    var deliveredMessageIDs: [String] { messages.map(\.id) }

    func record(_ state: SocketState) { states.append(state) }
    func record(_ message: SocketMessageEvent) { messages.append(message) }
    func recordAuthRequired() { authRequiredCount += 1 }
}

/// A client plus every fake it was built from; one `makeHarness()` per test.
struct SocketHarness {
    let scheduler: ManualScheduler
    let factory: FakeSocketTransportFactory
    let random: ScriptedRandomSource
    let store: FakeSocketStateStore
    let tokenStore: InMemoryAuthTokenStore
    let deviceInfo: DeviceInfoProviding
    let presenter: FakeNotificationPresenter
    let registry: SeenMessageRegistry
    let logger: RecordingLogger
    let recorder: StateRecorder
    let client: SocketClient

    /// Requires the harness to have started.
    var transport: FakeSocketTransport { factory.current! }

    var socketCount: Int { factory.createdCount }

    var pendingTimers: Int { scheduler.pendingTasks.count }

    func published(_ status: SocketStatus) -> Bool {
        recorder.statuses.contains(status)
    }

    var deliveredMessageIDs: [String] { recorder.deliveredMessageIDs }

    func reports(
        _ status: Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport.Status
    ) -> [Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport] {
        reports.filter { $0.status == status }
    }

    /// An hour: past 100 reconnect attempts at the 30 s cap.
    func advanceToNoFutureTimer() {
        scheduler.advance(by: 3_600_000)
    }

    var sentFrames: [Sinch_Push_Delivery_V1beta1_Ws_ClientFrame] { transport.sentFrames }

    var hellos: [Sinch_Push_Delivery_V1beta1_Ws_Hello] { transport.hellos }
    var hello: Sinch_Push_Delivery_V1beta1_Ws_Hello? { transport.hello }
    var polls: [Sinch_Push_Delivery_V1beta1_Ws_Poll] { transport.polls }
    var reports: [Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport] { transport.reports }
    var pongs: [Sinch_Push_Delivery_V1beta1_Ws_Pong] { transport.pongs }

    // MARK: - Inbound helpers

    @discardableResult
    func handshake(
        connectionID: String = "conn-1",
        pollIntervalMs: Int32 = 0,
        messages: [Sinch_Push_Delivery_V1beta1_Ws_PooledMessage] = []
    ) -> FakeSocketTransport {
        transport.openSocket()
        var ack = Sinch_Push_Delivery_V1beta1_Ws_HelloAck()
        ack.connectionID = connectionID
        ack.pollIntervalMs = pollIntervalMs
        ack.messages = messages
        transport.deliver(makeServerFrame(ack))
        return transport
    }

    func deliverMessage(
        _ pooled: Sinch_Push_Delivery_V1beta1_Ws_PooledMessage,
        ackToken: String = ""
    ) {
        var message = Sinch_Push_Delivery_V1beta1_Ws_Message()
        message.message = pooled
        message.ackToken = ackToken
        transport.deliver(makeServerFrame(message))
    }

    func ack(accepted: Bool, error: String = "", token: String) {
        var frame = Sinch_Push_Delivery_V1beta1_Ws_Ack()
        frame.ackToken = token
        frame.accepted = accepted
        frame.error = error
        transport.deliver(makeServerFrame(frame))
    }

    func serverClose(
        reason: Sinch_Push_Delivery_V1beta1_Ws_CloseReason,
        detail: String = ""
    ) {
        transport.serverClose(reason: reason, detail: detail)
    }
}

func makeHarness(
    configuration overrides: SocketConfiguration? = nil,
    random draw: Double = 0.5,
    store: FakeSocketStateStore = FakeSocketStateStore(),
    presenter: FakeNotificationPresenter? = nil,
    deviceInfo: DeviceInfoProviding = testDeviceInfo(),
    delivered: DeliveredNotificationLookup = NoDeliveredNotifications(),
    registry: SeenMessageRegistry? = nil,
    onMessage: (@Sendable (SocketMessageEvent) -> Void)? = nil,
    start: Bool = true
) -> SocketHarness {
    let scheduler = ManualScheduler()
    let factory = FakeSocketTransportFactory()
    let random = ScriptedRandomSource(fixed: draw)
    let tokenStore = InMemoryAuthTokenStore()
    let presenter = presenter ?? FakeNotificationPresenter()
    let logger = RecordingLogger()
    let recorder = StateRecorder()
    let registry = registry ?? SeenMessageRegistry(store: store)

    let client = SocketClient(
        configuration: overrides ?? testConfiguration(),
        transportFactory: factory,
        scheduler: scheduler,
        random: random,
        store: store,
        tokenStore: tokenStore,
        presenter: presenter,
        logger: logger,
        deviceInfo: deviceInfo,
        deliveredNotifications: delivered,
        seenRegistry: registry,
        callbacks: SocketClient.Callbacks(
            onState: { recorder.record($0) },
            onMessage: {
                recorder.record($0)
                onMessage?($0)
            },
            // `onLog` is not mirrored into `logger`: the client already writes to both sinks.
            onAuthRequired: { recorder.recordAuthRequired() }))
    if start { client.start() }

    return SocketHarness(
        scheduler: scheduler,
        factory: factory,
        random: random,
        store: store,
        tokenStore: tokenStore,
        deviceInfo: deviceInfo,
        presenter: presenter,
        registry: registry,
        logger: logger,
        recorder: recorder,
        client: client)
}

func testConfiguration(
    url: String = "ws://127.0.0.1:8080/ws",
    authToken: String = "jwt.token.value",
    projectID: String = "project-1",
    appID: String = "app-1",
    userID: String = "user-1",
    pollIntervalMs: Int = 0,
    displayNotifications: SocketDisplayRule = .always,
    sdkVersion: String? = nil
) -> SocketConfiguration {
    SocketConfiguration(
        url: url,
        authToken: authToken,
        projectID: projectID,
        appID: appID,
        userID: userID,
        pollIntervalMs: pollIntervalMs,
        displayNotifications: displayNotifications,
        sdkVersion: sdkVersion)
}
