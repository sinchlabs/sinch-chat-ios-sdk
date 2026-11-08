import Foundation
import Observation

/// The inbox without UI: the list of conversations as an observable model.
///
/// Create one with ``SinchInbox/makeInboxModel(options:)``, call ``start()``, and render ``chats``. Open a chat with
/// ``SinchInbox/makeConversation(inboxChat:)``.
///
/// The model loads the first page, keeps the list current from the server subscription (an updated chat moves to the
/// top), and reloads after the network returns or the app comes back to the foreground.
@MainActor
@Observable
public final class SinchInboxModel {

    /// The conversations, most recently updated first.
    public private(set) var chats: [InboxChat] = []
    public private(set) var isLoading = false
    /// Whether ``loadMore()`` can fetch another page.
    public private(set) var hasMore = true
    public private(set) var isOnline = true
    /// The last failure of loading or reloading the list, `nil` after a load succeeded. A reload that the network or
    /// foreground handling starts by itself has no caller to throw to; observe this instead.
    public private(set) var lastError: SinchHeadlessError?

    struct Timing: Sendable {
        var reconnectDelay: Duration = .seconds(1)
        var foregroundDelay: Duration = .milliseconds(500)
        static let standard = Timing()
    }

    let dataSource: InboxDataSource
    private let environment: any HeadlessEnvironment
    private let options: GetChatViewControllerOptions?
    private let timing: Timing
    private let tasks = HeadlessTaskBag()

    @ObservationIgnored private var channels: [Sinch_Chat_Sdk_V1alpha2_Channel] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var isMonitoring = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var startTask: Task<Void, any Error>?
    /// Identifies the run `start()` created, so a late-finishing old run never stops a newer one.
    @ObservationIgnored private var runCounter = 0
    /// Token of the next page; `nil` until the first page loaded. Owned here so an in-flight page cannot overwrite it
    /// after a reload reset it.
    @ObservationIgnored private var pageToken: String?

    /// Runs when `start()` actually starts the model (not when it joins a run or is already started): the place for
    /// what the creation of the model must not do yet, such as remembering the chat options.
    private let willStart: (@MainActor () -> Void)?

    init(dataSource: InboxDataSource,
         options: GetChatViewControllerOptions? = nil,
         environment: any HeadlessEnvironment = SystemHeadlessEnvironment(),
         timing: Timing = .standard,
         willStart: (@MainActor () -> Void)? = nil) {
        self.dataSource = dataSource
        self.options = options
        self.environment = environment
        self.timing = timing
        self.willStart = willStart
        dataSource.delegate = self
    }

    // MARK: - Public API

    /// Loads the first page and subscribes for updates. Idempotent: calling it while the first load runs waits for that
    /// load, and calling it when started returns at once. When the load fails the model stops itself and the error is
    /// thrown; calling ``start()`` again retries.
    ///
    /// Cancelling the task that called ``start()`` first abandons the start: the model is stopped and the call throws
    /// ``SinchHeadlessError/cancelled``. A caller that joined a run in progress only stops waiting when its own task is
    /// cancelled (it throws ``SinchHeadlessError/cancelled`` then); the run goes on.
    ///
    /// When the device goes offline, or the app to the background, while the first page loads, the load fails with
    /// ``SinchHeadlessError/offline`` like any other failed load: the model is stopped and ``lastError`` is set.
    ///
    /// - Throws: ``SinchHeadlessError``.
    public func start() async throws {
        if let startTask {
            return try await joinRun(startTask)
        }
        guard !isStarted else { return }
        willStart?()
        isStarted = true
        isSuspended = false
        armSubscriptionTeardown()
        beginMonitoring()
        runCounter += 1
        let run = runCounter
        let task = Task { @MainActor [weak self] in
            guard let self else { throw SinchHeadlessError.cancelled }
            do {
                try await self.reload()
                guard !Task.isCancelled else { throw SinchHeadlessError.cancelled }
            } catch {
                var mapped = Self.map(error)
                let isCurrent = self.isStarted && self.runCounter == run
                // Going offline or to the background tears the connection down, which supersedes the load that is
                // running: that is a failed load because of the connection, not a cancellation.
                if isCurrent, mapped == .cancelled, !Task.isCancelled, !self.isOnline || self.isSuspended {
                    mapped = .offline
                    self.lastError = mapped
                }
                // A failed load stops the model; so does a caller that gave up (its task was cancelled). A `stop()` from
                // outside has already cleared `isStarted`, and a newer run has another number.
                if isCurrent, Task.isCancelled || mapped != .cancelled {
                    self.stop()
                }
                throw mapped
            }
        }
        startTask = task
        defer { if startTask == task { startTask = nil } }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Loads the first page again, replacing ``chats``. While ``start()`` is still loading the first page, waits for
    /// that load instead: it is the refresh, and a second load would cancel it. Cancelling the calling task ends only
    /// that wait.
    public func refresh() async throws {
        guard isStarted else { throw SinchHeadlessError.notStarted }
        if let startTask {
            return try await joinRun(startTask)
        }
        try await reload()
    }

    /// Fetches the next page. Does nothing while loading or when ``hasMore`` is `false`.
    public func loadMore() async throws {
        guard isStarted else { throw SinchHeadlessError.notStarted }
        guard hasMore, !isLoading else { return }
        let gen = generation
        let token = pageToken
        isLoading = true
        defer { if gen == generation { isLoading = false } }
        let page: ChannelsPage
        do {
            page = try await dataSource.getChannelsPage(after: token)
        } catch InboxDataSourceError.noMoreChannels {
            if gen == generation { hasMore = false }
            return
        } catch {
            throw Self.map(error)
        }
        // A reload that started meanwhile owns the token now: this older page is dropped, not applied.
        guard gen == generation else { throw SinchHeadlessError.cancelled }
        pageToken = page.nextPageToken
        hasMore = !page.nextPageToken.isEmpty
        let known = Set(channels.map(\.channelID))
        channels.append(contentsOf: page.channels.filter { !known.contains($0.channelID) })
        publish()
    }

    /// Stops the subscription. Does not close the shared channel: a chat opened from the inbox is using it.
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        isSuspended = false
        isMonitoring = false
        generation &+= 1
        startTask?.cancel()
        startTask = nil
        tasks.cancelAll()
        dataSource.cancelSubscription()
        tasks.setReleaseAction(.started, nil)
        isLoading = false
    }

    /// While started, a model that is dropped without `stop()` still ends the server subscription: the data source's own
    /// task keeps the gRPC stream alive after the model's tasks are cancelled. Runs in `deinit`; `cancelSubscription()`
    /// is thread-safe.
    private func armSubscriptionTeardown() {
        let dataSource = self.dataSource
        tasks.setReleaseAction(.started) { dataSource.cancelSubscription() }
    }

    // MARK: - Loading

    private func reload() async throws {
        generation &+= 1
        let gen = generation
        dataSource.cancelSubscription()
        pageToken = nil
        liveIDs = []
        isLoading = true
        beginSubscription()
        defer { if gen == generation { isLoading = false } }
        let page: ChannelsPage
        do {
            page = try await dataSource.getChannelsPage(after: nil)
        } catch {
            let mapped = Self.map(error)
            if gen == generation, mapped != .cancelled { lastError = mapped }
            throw mapped
        }
        // Also dropped when the task that runs this load was cancelled (the caller of `start()` gave up).
        guard gen == generation, !Task.isCancelled else { throw SinchHeadlessError.cancelled }
        pageToken = page.nextPageToken
        hasMore = !page.nextPageToken.isEmpty
        lastError = nil
        var seen = Set<String>()
        var fresh = page.channels.filter { seen.insert($0.channelID).inserted }
        // Updates that arrived while the page loaded are newer than the page: keep them in front.
        let arrived = channels.filter { channel in !seen.contains(channel.channelID) && liveIDs.contains(channel.channelID) }
        fresh = arrived + fresh
        channels = fresh
        liveIDs = []
        publish()
    }

    @ObservationIgnored private var liveIDs: Set<String> = []

    private func beginSubscription() {
        let stream = dataSource.subscribeForChannels()
        tasks.set("subscription", Task { @MainActor [weak self] in
            do {
                for try await channel in stream {
                    guard let self else { return }
                    self.apply(channel)
                }
            } catch {
                chatLog(error)
            }
        })
    }

    /// Merges a channel update: an update of a listed chat is merged and moved to the top, a new chat goes to the top.
    private func apply(_ update: Sinch_Chat_Sdk_V1alpha2_Channel) {
        liveIDs.insert(update.channelID)
        if let row = channels.firstIndex(where: { $0.channelID == update.channelID }) {
            var channel = channels.remove(at: row)
            channel.updateChannel(channel: update)
            channels.insert(channel, at: 0)
        } else {
            channels.insert(update, at: 0)
        }
        publish()
    }

    private func publish() {
        chats = channels.map { InboxChat(channel: $0, options: options) }
    }

    fileprivate func subscriptionDropped() {
        guard isStarted, isOnline, !isSuspended else { return }
        let delay = timing.reconnectDelay
        tasks.set("resubscribe", Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isStarted, self.isOnline, !self.isSuspended else { return }
            self.dataSource.cancelSubscription()
            self.beginSubscription()
        })
    }

    // MARK: - Connectivity and app lifecycle

    private func beginMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let environment = self.environment
        tasks.set("connectivity", Task { @MainActor [weak self] in
            for await online in environment.connectivityUpdates() {
                guard let self else { return }
                self.handleConnectivity(online)
            }
        })
        tasks.set("lifecycle", Task { @MainActor [weak self] in
            for await event in environment.lifecycleUpdates() {
                guard let self else { return }
                self.handleLifecycle(event)
            }
        })
    }

    private func handleConnectivity(_ online: Bool) {
        let changed = online != isOnline
        isOnline = online
        guard changed, isStarted else { return }
        if online {
            resume()
        } else {
            generation &+= 1
            tasks.cancel("subscription")
            tasks.cancel("resubscribe")
            dataSource.cancelSubscription()
            isLoading = false
        }
    }

    private func handleLifecycle(_ event: HeadlessLifecycleEvent) {
        guard isStarted else { return }
        switch event {
        case .didEnterBackground:
            isSuspended = true
            generation &+= 1
            tasks.cancel("resume")
            tasks.cancel("subscription")
            tasks.cancel("resubscribe")
            dataSource.cancelSubscription()
            dataSource.closeChannel()
            isLoading = false
        case .willEnterForeground:
            guard isSuspended else { return }
            let delay = timing.foregroundDelay
            tasks.set("resume", Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.isStarted else { return }
                self.isSuspended = false
                self.dataSource.startChannel()
                self.resume()
            })
        }
    }

    private func resume() {
        guard isStarted, isOnline, !isSuspended else { return }
        tasks.set("reload", Task { @MainActor [weak self] in
            do {
                try await self?.reload()
            } catch {
                // `lastError` carries it for the host.
                chatLog(error)
            }
        })
    }

    static func map(_ error: any Error) -> SinchHeadlessError {
        switch error {
        case let error as SinchHeadlessError: return error
        case is CancellationError: return .cancelled
        case let error as InboxDataSourceError:
            switch error {
            case .notLoggedIn: return .notLoggedIn
            case .unknown(let inner): return .underlying(inner.localizedDescription)
            default: return .underlying(String(describing: error))
            }
        default: return .underlying(error.localizedDescription)
        }
    }
}

extension SinchInboxModel: InboxDataSourceDelegate {
    nonisolated func subscriptionError() {
        Task { @MainActor [weak self] in
            self?.subscriptionDropped()
        }
    }
}
