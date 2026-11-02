import Combine
import XCTest
@testable import SinchPushSDK

// MARK: - JWT

/// Creates an unsigned JWT for local claim-decoding tests.
func makeJWT(_ claims: [String: Any]) -> String {
    func segment(_ object: [String: Any]) -> String {
        // Sorted keys: two tokens built from equal claims must be equal (Dictionary order is per instance).
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            fatalError("the claims are not JSON-serializable: \(object)")
        }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    return [segment(["alg": "none"]), segment(claims), "sig"].joined(separator: ".")
}

func makeAuthModel(claims: [String: Any] = ["uuid": "user-1", "appId": "app-1", "projectId": "jwt-project"],
                   identity: SinchSDKIdentity = .selfSigned(userId: "user-1", secret: "s")) -> AuthModel {
    AuthModel(accessToken: makeJWT(claims), sinchIdentity: identity, clientID: "client", projectID: "project",
              configID: "cfg", region: relayRegion())
}

func relayRegion(isSecure: Bool? = true, relay: String? = "wss://relay.example.com/ws") -> Region {
    .custom(host: "h", pushAPIHost: "p", port: nil, isSecure: isSecure, relayURL: relay.flatMap(URL.init(string:)))
}

/// A custom region whose push host has no relay: the SDK cannot derive one for it.
func regionWithoutARelayHost() -> Region {
    .custom(host: "h", pushAPIHost: "grpc.sinch-push.unknown.example", port: nil, isSecure: true, relayURL: nil)
}

func makeAppConfig(region: Region = relayRegion(), relay: SinchSDKConfig.RelayOption = .enabled,
                   allowInsecureRelay: Bool = false) -> SinchSDKConfig.AppConfig {
    SinchSDKConfig.AppConfig(clientID: "client", projectID: "config-project", configID: "cfg", region: region,
                             relay: relay, allowInsecureRelay: allowInsecureRelay)
}

// MARK: - Fakes

final class InMemoryRelaySessionOwnerStore: RelaySessionOwnerStoring, @unchecked Sendable {
    private var owner: String?

    init(owner: String? = nil) {
        self.owner = owner
    }

    func loadOwner() -> String? { owner }
    func saveOwner(_ owner: String?) { self.owner = owner }
}

final class FakeAuthDataSource: AuthDataSource, @unchecked Sendable {
    var isLoggedIn = true
    var identityHashValue: String? = "hash"
    var currentConfigID = "cfg"
    var currentAuthorization: AuthModel?

    /// Results of successive `refreshToken()` calls; the last one repeats.
    var refreshResults: [Result<AuthModel, Error>] = []
    private(set) var refreshCount = 0

    /// When set, `refreshToken()` records the call and suspends until the test calls `finishRefresh(with:)`.
    var suspendsRefreshes = false
    private var suspendedRefreshes: [CheckedContinuation<AuthModel, Error>] = []
    private var refreshCallWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Main-actor isolated, like the manager's calling task: a test's main-queue drain orders against it.
    @MainActor
    func refreshToken() async throws -> AuthModel {
        refreshCount += 1
        let reached = refreshCallWaiters.filter { $0.count <= refreshCount }
        refreshCallWaiters.removeAll { $0.count <= refreshCount }
        reached.forEach { $0.continuation.resume() }
        if suspendsRefreshes {
            return try await withCheckedThrowingContinuation { suspendedRefreshes.append($0) }
        }
        let index = min(refreshCount, refreshResults.count) - 1
        guard index >= 0 else { throw AuthDataSourceError.notLoggedIn }
        return try refreshResults[index].get()
    }

    @MainActor
    func waitForRefreshCall(_ count: Int = 1) async {
        guard refreshCount < count else { return }
        await withCheckedContinuation { refreshCallWaiters.append((count, $0)) }
    }

    /// Number of refreshes started and not yet finished by the test.
    @MainActor
    var suspendedRefreshCount: Int { suspendedRefreshes.count }

    @MainActor
    func finishRefresh(with result: Result<AuthModel, Error>) {
        precondition(!suspendedRefreshes.isEmpty, "no refresh is suspended")
        suspendedRefreshes.removeFirst().resume(with: result)
    }

    func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity) async throws -> AuthModel {
        throw AuthDataSourceError.notLoggedIn
    }

    func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity,
                       completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        completion(.failure(.cannotEstablishConnection))
    }

    func currentAccessToken() throws -> String { "token" }
    func deleteToken() {}
}

/// Binds to the client like `UIApplicationSocketLifecycle` does; a test fires the transitions by hand.
@MainActor
final class FakeLifecycle: AppLifecycleObserving {
    var onBackground: (() -> Void)?
    var onForeground: (() -> Void)?
    private(set) var isObserving = false
    private(set) var startCount = 0

    init(client: SocketClient) {
        onBackground = { [weak client] in client?.suspend() }
        onForeground = { [weak client] in client?.resume() }
    }

    func startObserving() { isObserving = true; startCount += 1 }
    func stopObserving() { isObserving = false }
}

/// Mutable knobs the manager's injected closures read. Single-threaded in tests (main actor), hence unchecked.
final class RelayTestState: @unchecked Sendable {
    var lifecycles: [FakeLifecycle] = []
    var inAppResult: @Sendable ([String: String]) -> Bool = { _ in false }
    var inAppOffers: [[String: String]] = []
    var isInBackground = false
    var installationId: String? = "install-1"
    var installationIdReads = 0
    var log: [String] = []
}

/// Everything a manager test needs, over fakes: no network, no Keychain, no notification centre.
@MainActor
final class RelayTestHarness {
    let scheduler = ManualScheduler()
    let factory = FakeSocketTransportFactory()
    let store: FakeSocketStateStore
    let tokenStore = InMemoryAuthTokenStore()
    let presenter = FakeNotificationPresenter()
    let registry: SeenMessageRegistry
    let sessionOwner: InMemoryRelaySessionOwnerStore
    let auth = FakeAuthDataSource()
    let state = RelayTestState()
    let manager: PushSocketManager
    let settings: RelaySettings
    let defaultsSuite: String

    var lifecycles: [FakeLifecycle] { state.lifecycles }
    var lifecycle: FakeLifecycle? { state.lifecycles.last }
    var inAppOffers: [[String: String]] { state.inAppOffers }

    init(store: FakeSocketStateStore = FakeSocketStateStore(), owner: String? = nil) {
        self.store = store
        // A suite of its own: the runtime toggle is persisted and must not leak between tests (or into the app).
        defaultsSuite = "sinch.tests.relay.\(UUID().uuidString)"
        settings = RelaySettings(userDefaults: UserDefaults(suiteName: defaultsSuite)!)
        let registry = SeenMessageRegistry(store: store)
        self.registry = registry
        let sessionOwner = InMemoryRelaySessionOwnerStore(owner: owner)
        self.sessionOwner = sessionOwner
        presenter.acceptsPost = true
        let state = self.state
        let dependencies = PushSocketManager.Dependencies(
            transportFactory: factory,
            scheduler: scheduler,
            random: ScriptedRandomSource(fixed: 0.5),
            // Production wiring: assertions read the raw store, the client the configuration-less one.
            store: NonPersistingConfigurationStateStore(wrapping: store),
            tokenStore: tokenStore,
            presenter: presenter,
            deliveredNotifications: FakeDeliveredNotifications(),
            sessionOwner: sessionOwner,
            deviceInfo: testDeviceInfo(),
            logger: RecordingLogger(),
            registry: registry,
            makeLifecycle: { client in
                let lifecycle = FakeLifecycle(client: client)
                state.lifecycles.append(lifecycle)
                return lifecycle
            },
            isApplicationInBackground: { state.isInBackground },
            installationId: {
                state.installationIdReads += 1
                return state.installationId
            })
        manager = PushSocketManager(dependencies: dependencies, settings: settings, showInApp: { metadata in
            state.inAppOffers.append(metadata)
            return state.inAppResult(metadata)
        })
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    }

    func start(config: SinchSDKConfig.AppConfig = makeAppConfig(), auth model: AuthModel = makeAuthModel()) {
        manager.start(config: config, auth: model, authDataSource: auth)
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// `flush()` repeated: main-queue work enqueued by work that a previous pass ran (the manager's refresh task
    /// hops to the main actor twice) has run too. A negative assertion is made after this barrier.
    func settle(passes: Int = 5) async {
        for _ in 0..<passes { await flush() }
    }

    func handshake() async {
        factory.current?.openSocket()
        var ack = Sinch_Push_Delivery_V1beta1_Ws_HelloAck()
        ack.connectionID = "conn"
        factory.current?.deliver(makeServerFrame(ack))
        await flush()
    }

    func deliverMessage(id: String, metadata: [String: String] = [:], title: String = "Title") {
        var pooled = blankPooledMessage(messageID: id)
        pooled.pushNotification.alert.title = title
        pooled.pushNotification.metadata = metadata
        var message = Sinch_Push_Delivery_V1beta1_Ws_Message()
        message.message = pooled
        factory.current?.deliver(makeServerFrame(message))
    }
}

@MainActor
final class PublisherCollector<Value> {
    private(set) var values: [Value] = []
    private var cancellable: AnyCancellable?

    init<P: Publisher>(_ publisher: P) where P.Output == Value, P.Failure == Never {
        cancellable = publisher.sink { [weak self] value in
            MainActor.assumeIsolated { self?.values.append(value) }
        }
    }
}
