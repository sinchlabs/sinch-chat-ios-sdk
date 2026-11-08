// swiftlint:disable file_length type_body_length
import Foundation
import Observation

/// A chat conversation without UI: the logic of the chat screen as an observable model.
///
/// Create one with ``SinchChat/makeConversation(options:)`` (or ``SinchInbox/makeConversation(inboxChat:)``), call
/// ``start()``, and render ``messages`` and ``pending`` however you like. SwiftUI observes the properties directly;
/// UIKit can drive diffable data sources from ``updates``.
///
/// The model owns the parts the chat screen would otherwise own: the history paging, the subscription and its
/// reconnects, the optimistic send with its de-duplication against the server echo, the typing indicator, the network
/// monitor and the app foreground/background handling.
///
/// Only one chat can run at a time, as with the chat screen: a second ``SinchChat/makeConversation(options:)`` throws
/// ``SinchChatSDKError/unavailable`` until the running one is stopped.
@MainActor
@Observable
public final class SinchConversation {

    /// Where the connection is. This enum may gain cases in minor releases: include a `default:` in every `switch`
    /// over it.
    public enum Phase: Equatable, Sendable {
        /// Not started, or stopped.
        case idle
        /// Loading the first page, or reloading after a reconnect. Also while a started model waits for the network
        /// or the foreground: it has given the connection up (the subscription is closed and the "chat is running"
        /// flag released) and reloads by itself when the device is online and the app is active again.
        /// ``messages`` and ``pending`` stay readable meanwhile; sending throws ``SinchHeadlessError/offline``.
        case connecting
        /// History is loaded and the subscription is running.
        case ready
        /// Loading failed. ``start()`` can be called again; a restored network connection (or the app returning to the
        /// foreground) retries by itself. A load that the device going offline (or to the background) interrupted
        /// ends here with ``SinchHeadlessError/offline``.
        ///
        /// ``SinchHeadlessError/unavailable`` also appears here when a chat screen, opened or returning to the
        /// foreground, took the "chat is running" flag from a running conversation: it keeps its live subscription
        /// until its next reconnect, and then becomes `.failed(.unavailable)`.
        case failed(SinchHeadlessError)
    }

    // MARK: Observable state

    /// The messages in chronological order. System date separators are not included: group by
    /// `message.body.sendDate` yourself.
    public private(set) var messages: [Message] = []
    /// Outgoing messages that are not confirmed yet, oldest first. Render them after ``messages``.
    public private(set) var pending: [SinchPendingMessage] = []
    public private(set) var phase: Phase = .idle
    public private(set) var isLoadingHistory = false
    /// Whether ``loadMore()`` can fetch older messages.
    public private(set) var hasMoreHistory = true
    public private(set) var isAgentTyping = false
    public private(set) var isOnline = true

    /// Whether sending asks for the notification permission when it is not granted yet, as the chat screen does.
    /// Replies from an agent arrive as pushes, so this is on by default.
    @ObservationIgnored public var requestsPushPermissionOnSend = true

    /// A stream of changes to ``messages`` and ``pending`` for UIKit diffing. Every access returns a new stream, so
    /// there can be several subscribers; events from before the access are not replayed. Up to 256 undelivered events
    /// are buffered per stream; a stream that falls further behind gets a ``SinchConversationUpdate/reset(_:)`` that
    /// replaces what it missed.
    ///
    /// ``stop()`` ends every open stream, so a `for await` loop over it finishes; access `updates` again after the next
    /// ``start()``. ``phase``, ``isAgentTyping``, ``isOnline``, ``isLoadingHistory`` and ``hasMoreHistory`` are
    /// observable properties, not events: they never appear on this stream.
    public var updates: AsyncStream<SinchConversationUpdate> {
        broadcaster.makeStream()
    }

    // MARK: Internals

    struct Timing: Sendable {
        var typingTimeout: Duration = .seconds(30)
        /// A "typing" event this soon after a received message is ignored, as the chat screen does.
        var typingSuppression: TimeInterval = 1
        /// How long to wait for the server echo after the send call returned before confirming locally.
        var echoGrace: Duration = .seconds(3)
        var reconnectDelay: Duration = .seconds(1)
        var foregroundDelay: Duration = .milliseconds(500)
        /// How long a locally confirmed message still swallows a server echo that arrives under a different id.
        var tombstoneTTL: TimeInterval = 30

        static let standard = Timing()
    }

    /// Remembers the content of a message that was confirmed locally (no echo within the grace period), so a late echo
    /// carrying another entry id than the send answer is still recognized as that message.
    private struct Tombstone {
        let fingerprint: String
        /// The id the send call answered with. An echo under this id is the message itself and uses the tombstone up.
        let serverID: String
        let expires: Date
    }

    private enum Payload {
        case message(MessageType)
        case media(SinchMedia, uploadedURL: String?)
    }

    let dataSource: MessageDataSource
    private let environment: any HeadlessEnvironment
    private let pushPermission: PushNofiticationPermissionHandler?
    private let sendDocumentAsText: Bool
    private let isStartedFromInbox: Bool
    private let timing: Timing
    /// Runs when `start()` actually starts the model (not when it joins a run or is ready): the place for what the
    /// creation of the model must not do yet, such as remembering the chat options.
    private let willStart: (@MainActor () -> Void)?
    /// A history message counts as the delivery of a failed message only when it was sent between the creation of the
    /// failed message and its failure, give or take this: the pending message carries the device clock and the history
    /// the server's.
    private static let clockSlack: TimeInterval = 120
    /// Identifies this model as the owner of the "chat is running" flag.
    private let ownerToken = UUID()
    private let tasks = HeadlessTaskBag()
    private let broadcaster = UpdateBroadcaster<SinchConversationUpdate>()

    @ObservationIgnored private var startTask: Task<Void, any Error>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSuspended = false
    /// Set when the connection was given up (offline or background) while a load was running. A first-page load that
    /// ends `.cancelled` because of that reports `.offline`, also when the connection is back by the time it ends.
    @ObservationIgnored private var connectionLostUnderLoad = false
    @ObservationIgnored private var channelClosed = false
    @ObservationIgnored private var isMonitoring = false
    @ObservationIgnored private var holdsChat = false
    /// Token of the next history page; `nil` until the first page loaded. Owned here, not by the data source, so an
    /// in-flight page cannot overwrite it after a reload reset it.
    @ObservationIgnored private var historyToken: String?
    /// Bumped whenever the connection is torn down or reloaded, so late results of older loads are dropped.
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var liveBuffer: [Message] = []
    @ObservationIgnored private var knownEntryIDs: Set<String> = []
    @ObservationIgnored private var lastReceivedAt: Date?

    @ObservationIgnored private var tempIDCounter = 0
    @ObservationIgnored private var payloads: [String: Payload] = [:]
    /// tempID → content fingerprint, to match the echo of an outgoing message that arrives before the send call returns.
    @ObservationIgnored private var fingerprints: [String: String] = [:]
    /// server entry id → tempID, recorded when the send call returns.
    @ObservationIgnored private var serverIDs: [String: String] = [:]
    /// Messages that resolved a pending entry, for the send call that is still waiting to return. An entry exists only
    /// while that call is in `inFlight`.
    @ObservationIgnored private(set) var resolved: [String: Message] = [:]
    /// tempID → number of `transmit` calls that have not returned yet.
    @ObservationIgnored private var inFlight: [String: Int] = [:]
    /// tempIDs whose transport call is between dispatch and answer.
    @ObservationIgnored private var dispatched: Set<String> = []
    /// Failed tempIDs that the server may have accepted anyway (the call timed out or was cancelled after dispatch).
    /// Only these can be settled by the content of an echo; a message that failed before the network never went out.
    @ObservationIgnored private var mayHaveBeenDelivered: Set<String> = []
    /// tempID → when the entry failed. Closes the window in which a history message can count as its delivery.
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    /// tempID → ids of the listed outgoing messages with the same content, as of when the entry was added or failed.
    /// Those are other messages (an earlier "ok"), never the delivery of this one.
    @ObservationIgnored private var listedBefore: [String: Set<String>] = [:]
    @ObservationIgnored private var tombstones: [Tombstone] = []
    /// Identifies the run that `start()` created, so a late-finishing old run never stops a newer one.
    @ObservationIgnored private var runCounter = 0
    /// The last typing send; the next one waits for it, so "started" and "ended" reach the server in order.
    @ObservationIgnored private var typingTask: Task<Void, Never>?

    init(dataSource: MessageDataSource,
         environment: any HeadlessEnvironment = SystemHeadlessEnvironment(),
         pushPermission: PushNofiticationPermissionHandler? = DefaultPushPermissionHandler(),
         sendDocumentAsText: Bool = false,
         isStartedFromInbox: Bool = false,
         timing: Timing = .standard,
         willStart: (@MainActor () -> Void)? = nil) {
        self.dataSource = dataSource
        self.environment = environment
        self.pushPermission = pushPermission
        self.sendDocumentAsText = sendDocumentAsText
        self.isStartedFromInbox = isStartedFromInbox
        self.timing = timing
        self.willStart = willStart
        dataSource.delegate = self
    }

    // MARK: - Lifecycle

    /// Loads the first page of history and subscribes for new messages. Idempotent: calling it while it is running
    /// waits for that run, and calling it when ready returns at once.
    ///
    /// Cancelling the task that called ``start()`` first abandons the start: the model is stopped as by ``stop()`` and
    /// the call throws ``SinchHeadlessError/cancelled``. A caller that joined a run already in progress only stops
    /// waiting for it when its own task is cancelled (it throws ``SinchHeadlessError/cancelled`` then); the run goes
    /// on.
    ///
    /// When the device goes offline, or the app to the background, while the first page loads, the call throws
    /// ``SinchHeadlessError/offline`` and ``phase`` is `.failed(.offline)`; the model stays started and reloads by
    /// itself when the connection (or the foreground) is back. This also holds when the connection is already back
    /// by the time the interrupted load ends: the call still throws ``SinchHeadlessError/offline``, and the reload
    /// that the model started meanwhile sets ``phase``.
    ///
    /// On a started model that is waiting for the foreground (the app went to the background), the call throws
    /// ``SinchHeadlessError/offline`` at once: the model reloads by itself when the app is active again.
    ///
    /// - Throws: ``SinchHeadlessError`` when the first page cannot be loaded. ``phase`` is then `.failed`, and
    ///   calling ``start()`` again retries. ``SinchHeadlessError/unavailable`` when another chat is running, and
    ///   ``SinchHeadlessError/cancelled`` when ``stop()`` was called meanwhile.
    public func start() async throws {
        if let startTask {
            return try await joinRun(startTask)
        }
        if phase == .ready { return }
        // Started but suspended in the background: loading now would open the connection a backgrounded app has given up.
        if isStarted, isSuspended { throw SinchHeadlessError.offline }
        guard acquireChat() else { throw SinchHeadlessError.unavailable }
        willStart?()

        // Everything `stop()` looks at is set before the first suspension, so a stop right after this call cancels the run.
        isStarted = true
        phase = .connecting
        armStartedTeardown()
        runCounter += 1
        let run = runCounter
        let task = Task { @MainActor [weak self] in
            guard let self else { throw SinchHeadlessError.cancelled }
            do {
                try await self.performStart()
            } catch {
                // The caller gave up (its task was cancelled) while this run is still the current one.
                if Task.isCancelled, self.isStarted, self.runCounter == run { self.stop() }
                throw error
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

    /// Closes the channel and releases the conversation, as closing the chat screen does, and posts
    /// ``SinchPluginEvent/didCloseChat``. ``messages`` stay readable. Messages that were still being sent are marked
    /// `.failed` in ``pending``, except those the server already accepted. Open ``updates`` streams end.
    /// ``start()`` can be called again.
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        isSuspended = false
        isMonitoring = false
        generation &+= 1
        startTask?.cancel()
        startTask = nil
        // Every link of the typing chain checks `isStarted` and the generation before it sends, so the ones queued
        // behind the running link drop out too; cancelling the last link would leave the others to run.
        typingTask?.cancel()
        typingTask = nil
        tasks.cancelAll()
        dataSource.cancelCalls()
        dataSource.cancelSubscription()
        if !isStartedFromInbox {
            dataSource.closeChannel()
            channelClosed = true
        }
        isAgentTyping = false
        isLoadingHistory = false
        isReloading = false
        liveBuffer = []
        resolved = [:]
        tombstones = []
        settlePendingAfterStop()
        phase = .idle
        // The teardown of a dropped model has been done right here.
        tasks.setReleaseAction(.started, nil)
        releaseChat()
        environment.post(.didCloseChat)
        broadcaster.finishAll()
    }

    private func performStart() async throws {
        guard isStarted, !Task.isCancelled else { throw SinchHeadlessError.cancelled }
        if channelClosed {
            dataSource.startChannel()
            channelClosed = false
        }
        beginMonitoring()
        connectionLostUnderLoad = false
        do {
            try await reload()
            guard isStarted, !Task.isCancelled else { throw SinchHeadlessError.cancelled }
            phase = .ready
        } catch {
            let mapped = Self.map(error)
            // Stopped (or abandoned by the caller) while loading: whatever the load ended with, the run was cancelled.
            guard isStarted, !Task.isCancelled else { throw SinchHeadlessError.cancelled }
            var failure = mapped
            if mapped == .cancelled {
                // Offline or in the background, the connection was torn down under the load: that is what failed it.
                // (Online and active again, a newer reload took over and reports through `phase`; the call still
                // says what interrupted it.)
                guard !isOnline || isSuspended else { throw connectionLostUnderLoad ? SinchHeadlessError.offline : mapped }
                failure = .offline
            }
            enterFailed(failure)
            throw failure
        }
    }

    /// Loading failed: stop what runs and give the "chat is running" flag back (foreground pushes and the chat screen
    /// work again), as the chat screen does. The model stays started, so a restored connection reloads.
    private func enterFailed(_ error: SinchHeadlessError) {
        tearDownConnection()
        releaseChat()
        phase = .failed(error)
    }

    private func tearDownConnection() {
        generation &+= 1
        tasks.cancel("subscription")
        tasks.cancel("resubscribe")
        dataSource.cancelCalls()
        dataSource.cancelSubscription()
        isReloading = false
        isLoadingHistory = false
        liveBuffer = []
    }

    // MARK: Ownership of the "chat is running" flag

    /// Claims the flag. `false` when another chat holds it. The environment is asked every time, also while this model
    /// believes it holds the flag: the chat screen overwrites the flag without asking (and without this model's token),
    /// and then this model has lost the claim, however long ago it made it.
    ///
    /// While the claim is held, a model that is dropped without `stop()` gives the flag back.
    private func acquireChat() -> Bool {
        guard environment.claimChat(owner: ownerToken) else {
            if holdsChat {
                holdsChat = false
                tasks.setReleaseAction(.claim, nil)
            }
            return false
        }
        guard !holdsChat else { return true }
        holdsChat = true
        let environment = self.environment
        let owner = ownerToken
        // Runs in `deinit`, on whatever thread released the model: the environment is main-actor bound, so the release
        // hops. It lands a moment after the model is gone; the token makes a late release harmless to a newer claim.
        tasks.setReleaseAction(.claim) {
            Task { @MainActor in
                environment.releaseChat(owner: owner)
            }
        }
        return true
    }

    /// What `start()` opened and `stop()` closes. Independent of the claim: a model that went offline, to the background
    /// or into `.failed` has given the flag back but is still started, and when it is dropped like that it still has to
    /// close the subscription and the channel and tell the host.
    private func armStartedTeardown() {
        let environment = self.environment
        let dataSource = self.dataSource
        let closesChannel = !isStartedFromInbox
        tasks.setReleaseAction(.started) {
            dataSource.cancelSubscription()
            if closesChannel { dataSource.closeChannel() }
            Task { @MainActor in
                environment.post(.didCloseChat)
            }
        }
    }

    private func releaseChat() {
        guard holdsChat else { return }
        holdsChat = false
        tasks.setReleaseAction(.claim, nil)
        environment.releaseChat(owner: ownerToken)
    }

    /// After `stop()`: a message the server already accepted leaves the list (a later load brings it back from the
    /// history); one that was still being sent becomes `.failed`, so it can be retried after a restart.
    private func settlePendingAfterStop() {
        let acknowledged = Set(serverIDs.values)
        for item in pending {
            if acknowledged.contains(item.tempID) {
                forgetPending(item.tempID)
                emit(.pendingRemoved(tempID: item.tempID))
            } else if item.status == .sending {
                // The transport call keeps running after the stop and may still deliver the message.
                if dispatched.contains(item.tempID) { mayHaveBeenDelivered.insert(item.tempID) }
                recordFailure(of: item.tempID)
                updatePending(item.tempID) {
                    $0.status = .failed
                    $0.error = .cancelled
                }
            }
        }
    }

    // MARK: - History

    /// Fetches the next page of older messages. Does nothing while a page is loading or when ``hasMoreHistory`` is
    /// `false`.
    ///
    /// - Throws: ``SinchHeadlessError/notStarted`` unless ``phase`` is `.ready`, and ``SinchHeadlessError/offline``
    ///   while the device is offline or the app is in the background.
    public func loadMore() async throws {
        guard isStarted else { throw SinchHeadlessError.notStarted }
        guard isOnline, !isSuspended else { throw SinchHeadlessError.offline }
        guard phase == .ready else { throw SinchHeadlessError.notStarted }
        guard hasMoreHistory, !isLoadingHistory, !isReloading else { return }
        let gen = generation
        let token = historyToken
        isLoadingHistory = true
        defer { if gen == generation { isLoadingHistory = false } }

        let page: MessageHistoryPage
        do {
            page = try await dataSource.getMessageHistoryPage(after: token)
        } catch MessageDataSourceError.noMoreMessages {
            if gen == generation { hasMoreHistory = false }
            return
        } catch {
            throw Self.map(error)
        }
        // A reload that started meanwhile owns the token now: this older page is dropped, not applied.
        guard gen == generation else { throw SinchHeadlessError.cancelled }
        historyToken = page.nextPageToken
        hasMoreHistory = !page.nextPageToken.isEmpty
        let older = processHistory(page.messages)
        guard !older.isEmpty else { return }
        messages = older + messages
        emit(.prepended(older))
    }

    /// Resets the connection and loads the first page; live messages that arrive meanwhile are applied afterwards.
    private func reload() async throws {
        generation &+= 1
        let gen = generation
        dataSource.cancelCalls()
        dataSource.cancelSubscription()
        liveBuffer = []
        historyToken = nil
        // The history that follows lists what the server has; a late echo of an older message is not expected after it.
        tombstones = []
        isReloading = true
        isLoadingHistory = true
        beginSubscription()
        defer { if gen == generation { isLoadingHistory = false } }

        let page: MessageHistoryPage
        do {
            page = try await dataSource.getMessageHistoryPage(after: nil)
        } catch {
            guard gen == generation else { throw SinchHeadlessError.cancelled }
            isReloading = false
            throw Self.map(error)
        }
        // Also dropped when the task that runs this load was cancelled (the caller of `start()` gave up).
        guard gen == generation, !Task.isCancelled else { throw SinchHeadlessError.cancelled }

        historyToken = page.nextPageToken
        hasMoreHistory = !page.nextPageToken.isEmpty
        knownEntryIDs = []
        let fresh = processHistory(page.messages)
        messages = fresh
        emit(.reset(fresh))
        isReloading = false
        let buffered = liveBuffer
        liveBuffer = []
        for message in buffered { handleLive(message) }
    }

    /// Drops what a list should not show, and settles pending messages the history already contains.
    private func processHistory(_ page: [Message]) -> [Message] {
        var result: [Message] = []
        for message in page {
            if let event = message.body as? MessageEvent, event.text?.isEmpty ?? true { continue }
            if message.body is MessageDate { continue }
            guard knownEntryIDs.insert(message.entryId).inserted else { continue }
            // Still-sending messages are matched by content. A failed message is matched only when its call may have
            // reached the server (it went out and ended without an answer, as after `stop()`) and the history message
            // is another message than one listed before and falls into its time window: an identical text from earlier
            // or later must not swallow a message never sent.
            if case .outgoing = message.owner,
               let tempID = pendingMatch(for: message, includeFailed: false) ?? deliveredFailedMatch(for: message) {
                forgetPending(tempID)
                if inFlight[tempID, default: 0] > 0 { resolved[tempID] = message }
                emit(.pendingRemoved(tempID: tempID))
            }
            result.append(message)
        }
        return result
    }

    // MARK: - Subscription

    private func beginSubscription() {
        let stream = dataSource.subscribeForMessages()
        tasks.set("subscription", Task { @MainActor [weak self] in
            do {
                for try await message in stream {
                    guard let self else { return }
                    self.handleLive(message)
                }
            } catch {
                chatLog(error)
            }
        })
    }

    private func handleLive(_ message: Message) {
        if isReloading {
            liveBuffer.append(message)
            return
        }

        if let event = message.body as? MessageEvent {
            switch event.type {
            case .composeStarted:
                agentStartedTyping()
                return
            case .composeEnd:
                agentStoppedTyping()
                return
            default:
                if event.text?.isEmpty ?? true { return }
            }
        }

        if case .outgoing = message.owner, absorbsOutgoingEcho(message) { return }

        guard knownEntryIDs.insert(message.entryId).inserted else { return }
        if case .incoming = message.owner {
            lastReceivedAt = Date()
            agentStoppedTyping()
        }
        messages.append(message)
        emit(.appended(message))
    }

    /// `true` when an outgoing message from the stream is the echo of something this model sent, and so is not new.
    private func absorbsOutgoingEcho(_ message: Message) -> Bool {
        // An echo under the id the send call answered with is the locally confirmed message itself: it uses up
        // its tombstone, so the same text from another device afterwards is a new message.
        tombstones.removeAll { $0.serverID == message.entryId }
        // A repeated echo of a listed message must not settle another pending message with the same text.
        if knownEntryIDs.contains(message.entryId), serverIDs[message.entryId] == nil { return true }
        // In this order: still-sending messages and the send answer's id first, then a locally confirmed message
        // whose echo came under another id, and only then a failed message the server may have taken after all.
        if resolveEcho(message, includeFailed: false) { return true }
        if consumeTombstone(for: message) {
            knownEntryIDs.insert(message.entryId)
            return true
        }
        return resolveEcho(message, includeFailed: true)
    }

    private func agentStartedTyping() {
        if let last = lastReceivedAt, Date().timeIntervalSince(last) < timing.typingSuppression { return }
        isAgentTyping = true
        let timeout = timing.typingTimeout
        tasks.set("typing", Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.isAgentTyping = false
        })
    }

    private func agentStoppedTyping() {
        tasks.cancel("typing")
        if isAgentTyping { isAgentTyping = false }
    }

    fileprivate func subscriptionDropped() {
        guard isStarted, isOnline, !isSuspended, !isReloading else { return }
        let delay = timing.reconnectDelay
        tasks.set("resubscribe", Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isStarted, self.isOnline, !self.isSuspended else { return }
            // The dropped stream may still occupy the data source's slot, and a second subscribe would then end at once.
            self.dataSource.cancelSubscription()
            self.beginSubscription()
        })
    }

    // MARK: - Sending

    /// Sends a text message. The message appears in ``pending`` at once and moves to ``messages`` when the server
    /// confirms it.
    ///
    /// - Returns: The sent message with the server-assigned `entryId`.
    /// - Throws: ``SinchHeadlessError``. A failed message stays in ``pending`` with status `.failed`.
    @discardableResult
    public func send(text: String) async throws -> Message {
        try ensureCanSend()
        let body = MessageText(text: text, sendDate: Self.now)
        let tempID = addPending(body: body, payload: .message(.text(text)))
        return try await transmit(tempID)
    }

    /// Uploads and sends an attachment. The pending message is added before the upload starts.
    @discardableResult
    public func send(_ media: SinchMedia) async throws -> Message {
        try ensureCanSend()
        let body = MessageMedia(url: media.localURLString, sendDate: Self.now, type: media.messageMediaType)
        let tempID = addPending(body: body, payload: .media(media, uploadedURL: nil), fingerprint: false)
        return try await transmit(tempID)
    }

    /// Sends a location. `title` and `label` default to the SDK's localized strings for an outgoing location, in the
    /// default localization (`SinchSDKConfig.LocalizationConfig.defaultValue`): a custom `localizationConfig` passed to
    /// the chat screen does not reach the headless model, so pass `title` and `label` yourself to localize them.
    @discardableResult
    public func sendLocation(latitude: Double, longitude: Double,
                             title: String? = nil, label: String? = nil) async throws -> Message {
        try ensureCanSend()
        var config = SinchSDKConfig.LocalizationConfig.defaultValue
        if let title { config.outgoingLocationMessageTitle = title }
        if let label { config.outgoingLocationMessageButtonTitle = label }
        let float = (latitude: Float(latitude), longitude: Float(longitude))
        let body = MessageLocation(label: config.outgoingLocationMessageButtonTitle,
                                   title: config.outgoingLocationMessageTitle,
                                   latitude: Double(float.latitude), longitude: Double(float.longitude),
                                   sendDate: Self.now)
        let message = MessageType.location(latitude: float.latitude, longitude: float.longitude,
                                           localizationConfig: config)
        let tempID = addPending(body: body, payload: .message(message))
        return try await transmit(tempID)
    }

    /// Answers a quick-reply choice of a choice or card message. Nothing is added to ``messages``: the server does
    /// not echo a choice response as a message.
    public func sendChoice(postback: String, messageID: String) async throws {
        try ensureCanSend()
        do {
            _ = try await dataSource.sendMessage(.choiceResponseMessage(postbackData: postback, entryID: messageID))
        } catch {
            throw Self.map(error)
        }
    }

    /// Answers a ``SinchChoice/reply(text:postback:messageID:)``. Any other kind of choice is an action for the host
    /// app (open a URL, dial, show a place): this call does nothing for it, silently, and does not throw. Check the
    /// kind first (the demo app opens URLs and dials itself).
    public func sendChoice(_ choice: SinchChoice) async throws {
        guard case let .reply(_, postback, messageID) = choice else { return }
        try await sendChoice(postback: postback, messageID: messageID)
    }

    /// Tells the agent that the user is typing (`true`) or stopped (`false`). Fire and forget; does nothing unless
    /// ``phase`` is `.ready` (not started, loading, failed, offline or in the background).
    public func sendTyping(_ isTyping: Bool) {
        guard isStarted, isOnline, !isSuspended, phase == .ready else { return }
        let dataSource = self.dataSource
        let previous = typingTask
        let gen = generation
        // One chain: each send waits for the one before it, so "started" and "ended" cannot reach the server reordered.
        // Every link re-checks after the wait: `stop()` (or a reconnect) can come while an earlier link is still running,
        // and only the last link is cancelled by `stop()`.
        typingTask = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled, self?.isStarted == true, self?.generation == gen else { return }
            do {
                try await dataSource.sendEvent(isTyping ? .composeStarted : .composeEnd)
            } catch {
                chatLog(error)
            }
        }
    }

    /// Sends a failed pending message again, keeping its place and `tempID`.
    ///
    /// - Throws: ``SinchHeadlessError/unknownPendingMessage`` when the message is not failed, and also while the
    ///   call that failed it is still running: after ``stop()`` a send that was in flight is marked failed at once,
    ///   but its transport call can still complete, and sending it again meanwhile would send it twice.
    @discardableResult
    public func retry(_ tempID: String) async throws -> Message {
        guard let index = pending.firstIndex(where: { $0.tempID == tempID }),
              pending[index].status == .failed, payloads[tempID] != nil,
              inFlight[tempID, default: 0] == 0 else {
            throw SinchHeadlessError.unknownPendingMessage
        }
        try ensureCanSend()
        mayHaveBeenDelivered.remove(tempID)
        pending[index].status = .sending
        pending[index].error = nil
        emit(.pendingUpdated(pending[index]))
        return try await transmit(tempID)
    }

    /// Removes a failed pending message without sending it.
    public func discard(_ tempID: String) {
        guard let index = pending.firstIndex(where: { $0.tempID == tempID }), pending[index].status == .failed else { return }
        forgetPending(tempID)
        emit(.pendingRemoved(tempID: tempID))
    }

    private func ensureCanSend() throws {
        guard isStarted, phase != .idle else { throw SinchHeadlessError.notStarted }
        // In the background the connection is closed although the network is up: sending would only fail late.
        guard isOnline, !isSuspended else { throw SinchHeadlessError.offline }
        guard !isFailedPhase else { throw SinchHeadlessError.notStarted }
        askForNotificationsIfNeeded()
    }

    private var isFailedPhase: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func askForNotificationsIfNeeded() {
        guard requestsPushPermissionOnSend, let handler = pushPermission else { return }
        handler.checkIfPermissionIsGranted { status in
            switch status {
            case .granted: break
            case .denied, .notDetermined: handler.askForPermissions(completion: nil)
            @unknown default: break
            }
        }
    }

    // MARK: Pending bookkeeping

    private func addPending(body: any MessageBody, payload: Payload, fingerprint: Bool = true) -> String {
        tempIDCounter += 1
        let tempID = "tmp-\(tempIDCounter)"
        let item = SinchPendingMessage(tempID: tempID, body: body, status: .sending, error: nil, createdAt: Date())
        payloads[tempID] = payload
        if fingerprint, let print = Self.fingerprint(of: body) { fingerprints[tempID] = print }
        snapshotListedMessages(for: tempID)
        pending.append(item)
        emit(.pendingAdded(item))
        return tempID
    }

    /// Notes when the entry failed and which same-content messages are listed by now, for the settle by history.
    private func recordFailure(of tempID: String) {
        failedAt[tempID] = Date()
        snapshotListedMessages(for: tempID)
    }

    /// Remembers the listed outgoing messages with this entry's content: they exist already, so a history message with
    /// one of those ids is not the delivery of this entry (an earlier "ok" is not the failed "ok").
    private func snapshotListedMessages(for tempID: String) {
        guard let print = fingerprints[tempID] else { return }
        for message in messages {
            guard case .outgoing = message.owner, Self.fingerprint(of: message.body) == print else { continue }
            listedBefore[tempID, default: []].insert(message.entryId)
        }
    }

    private func forgetPending(_ tempID: String) {
        pending.removeAll { $0.tempID == tempID }
        payloads[tempID] = nil
        fingerprints[tempID] = nil
        failedAt[tempID] = nil
        listedBefore[tempID] = nil
        mayHaveBeenDelivered.remove(tempID)
        serverIDs = serverIDs.filter { $0.value != tempID }
        tasks.cancel("grace-\(tempID)")
    }

    private func updatePending(_ tempID: String, _ change: (inout SinchPendingMessage) -> Void) {
        guard let index = pending.firstIndex(where: { $0.tempID == tempID }) else { return }
        change(&pending[index])
        emit(.pendingUpdated(pending[index]))
    }

    private func transmit(_ tempID: String) async throws -> Message {
        inFlight[tempID, default: 0] += 1
        defer {
            inFlight[tempID, default: 1] -= 1
            if inFlight[tempID, default: 0] <= 0 {
                inFlight[tempID] = nil
                resolved[tempID] = nil
            }
        }
        var wasDispatched = false
        do {
            let messageType = try await prepare(tempID)
            wasDispatched = true
            dispatched.insert(tempID)
            defer { dispatched.remove(tempID) }
            let serverID = try await dataSource.sendMessage(messageType)
            return finishSend(tempID: tempID, serverID: serverID)
        } catch {
            let mapped = Self.map(error)
            if pending.contains(where: { $0.tempID == tempID }) {
                // Only a call that went out and ended without an answer (timeout, cancellation, lost connection) can have
                // delivered the message; an error before the network cannot, and its echo must not settle this entry.
                if wasDispatched, Self.mayHaveReachedServer(error) { mayHaveBeenDelivered.insert(tempID) }
                recordFailure(of: tempID)
                updatePending(tempID) {
                    $0.status = .failed
                    $0.error = mapped
                }
                serverIDs = serverIDs.filter { $0.value != tempID }
                // The fingerprint stays: the server may have taken the message after all, and its echo settles this entry.
            }
            throw mapped
        }
    }

    private static func mayHaveReachedServer(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? MessageDataSourceError)?.mayHaveReachedServer ?? false
    }

    /// Uploads the media if needed and returns what to send.
    private func prepare(_ tempID: String) async throws -> MessageType {
        switch payloads[tempID] {
        case let .message(type):
            if let print = pending.first(where: { $0.tempID == tempID }).flatMap({ Self.fingerprint(of: $0.body) }) {
                fingerprints[tempID] = print
            }
            return type
        case let .media(media, uploaded):
            let url: String
            if let uploaded {
                url = uploaded
            } else {
                guard let mediaType = media.mediaType else { throw SinchHeadlessError.unsupportedMedia }
                url = try await dataSource.uploadMedia(mediaType)
                guard pending.contains(where: { $0.tempID == tempID }) else { throw SinchHeadlessError.cancelled }
                payloads[tempID] = .media(media, uploadedURL: url)
            }
            let date = pending.first(where: { $0.tempID == tempID })?.body.sendDate ?? Self.now
            let body: any MessageBody
            let messageType: MessageType
            if sendDocumentAsText, media.isFile {
                body = MessageText(text: url, sendDate: date)
                messageType = .text(url)
            } else {
                let mediaBody = MessageMedia(url: url, sendDate: date, type: media.messageMediaType)
                body = mediaBody
                messageType = .media(message: Message(entryId: tempID, owner: .outgoing, body: mediaBody,
                                                      status: .sending))
            }
            updatePending(tempID) { $0.body = body }
            fingerprints[tempID] = Self.fingerprint(of: body)
            return messageType
        case nil:
            throw SinchHeadlessError.cancelled
        }
    }

    private func finishSend(tempID: String, serverID: String) -> Message {
        if let message = resolved.removeValue(forKey: tempID) {
            return message
        }
        guard let item = pending.first(where: { $0.tempID == tempID }) else {
            return Message(entryId: serverID, owner: .outgoing, body: MessageText(text: ""), status: .sent)
        }
        guard isStarted else {
            // Stopped while the call was in flight: the server has the message, but nothing is appended to a stopped
            // model. The entry leaves the list; the history brings the message back after a restart.
            forgetPending(tempID)
            emit(.pendingRemoved(tempID: tempID))
            return Message(entryId: serverID, owner: .outgoing, body: item.body, status: .sent)
        }
        serverIDs[serverID] = tempID
        let grace = timing.echoGrace
        tasks.set("grace-\(tempID)", Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            self?.confirmLocally(tempID: tempID, serverID: serverID)
        })
        return Message(entryId: serverID, owner: .outgoing, body: item.body, status: .sent)
    }

    /// The echo did not arrive within the grace period (subscription down, say): trust the send call's answer.
    private func confirmLocally(tempID: String, serverID: String) {
        guard isStarted, let item = pending.first(where: { $0.tempID == tempID }) else { return }
        if let print = Self.fingerprint(of: item.body) {
            let now = Date()
            tombstones.removeAll { $0.expires < now }
            tombstones.append(Tombstone(fingerprint: print, serverID: serverID,
                                        expires: now.addingTimeInterval(timing.tombstoneTTL)))
        }
        settle(tempID: tempID, with: Message(entryId: serverID, owner: .outgoing, body: item.body, status: .sent))
    }

    // MARK: Echo matching

    /// Finds the pending message that an outgoing message from the stream confirms. The send call's answer may not
    /// have arrived yet, so besides the server id the content is matched too (first in line wins).
    ///
    /// The date is left out of the content fingerprint on purpose: the pending message carries the device clock and
    /// the echo the server's.
    ///
    /// A message that failed locally can still be the one the server accepted (the answer got lost), so with
    /// `includeFailed` its echo settles it too, and Retry does not send it twice. Only a failed message whose call
    /// may have reached the server qualifies (`mayHaveBeenDelivered`): one that failed before the network never went
    /// out, so a message with the same text from elsewhere is not it. Messages still sending come first.
    private func pendingMatch(for message: Message, includeFailed: Bool = true) -> String? {
        if let tempID = serverIDs[message.entryId], pending.contains(where: { $0.tempID == tempID }) {
            return tempID
        }
        guard let print = Self.fingerprint(of: message.body) else { return nil }
        let sending = pending.first { $0.status == .sending && fingerprints[$0.tempID] == print }
        if let sending { return sending.tempID }
        guard includeFailed else { return nil }
        return pending.first {
            $0.status == .failed && mayHaveBeenDelivered.contains($0.tempID) && fingerprints[$0.tempID] == print
                && !wasListedBefore(message.entryId, for: $0.tempID)
        }?.tempID
    }

    private func wasListedBefore(_ entryID: String, for tempID: String) -> Bool {
        listedBefore[tempID]?.contains(entryID) ?? false
    }

    /// The failed pending message that a history message settles: one whose call may have reached the server, with the
    /// same content, that the history message is not an already listed message of (`listedBefore`), and that was sent
    /// between the creation of the pending message and its failure (each within `clockSlack`). History messages
    /// without a date match nothing.
    private func deliveredFailedMatch(for message: Message) -> String? {
        guard let sent = message.body.sendDate, let print = Self.fingerprint(of: message.body) else { return nil }
        let sentAt = TimeInterval(sent)
        return pending.first {
            guard $0.status == .failed, mayHaveBeenDelivered.contains($0.tempID), fingerprints[$0.tempID] == print,
                  !wasListedBefore(message.entryId, for: $0.tempID) else { return false }
            let failed = failedAt[$0.tempID] ?? .distantFuture
            return sentAt >= $0.createdAt.timeIntervalSince1970 - Self.clockSlack
                && sentAt <= failed.timeIntervalSince1970 + Self.clockSlack
        }?.tempID
    }

    /// `true` once for each locally confirmed message whose echo arrives under another id than the send answer.
    private func consumeTombstone(for message: Message) -> Bool {
        let now = Date()
        tombstones.removeAll { $0.expires < now }
        guard let print = Self.fingerprint(of: message.body),
              let index = tombstones.firstIndex(where: { $0.fingerprint == print }) else { return false }
        tombstones.remove(at: index)
        return true
    }

    private func resolveEcho(_ message: Message, includeFailed: Bool) -> Bool {
        guard let tempID = pendingMatch(for: message, includeFailed: includeFailed) else { return false }
        var confirmed = message
        confirmed.status = .sent
        settle(tempID: tempID, with: confirmed)
        return true
    }

    private func settle(tempID: String, with message: Message) {
        forgetPending(tempID)
        if inFlight[tempID, default: 0] > 0 { resolved[tempID] = message }
        guard knownEntryIDs.insert(message.entryId).inserted else {
            // Already listed (the history or a previous echo): the pending entry just goes away.
            emit(.resolved(tempID: tempID, message: message))
            return
        }
        messages.append(message)
        emit(.resolved(tempID: tempID, message: message))
    }

    private static func fingerprint(of body: any MessageBody) -> String? {
        switch body {
        case let text as MessageText: return "text:\(text.text)"
        case let media as MessageMedia: return "media:\(media.url)"
        case let location as MessageLocation: return "loc:\(location.latitude):\(location.longitude)"
        default: return nil
        }
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
        environment.post(.didChangeInternetState(isOn: online))
        guard changed, isStarted else { return }
        if online {
            resume()
        } else {
            // Like the chat screen: stop the stream and give the running flag back. Pending messages stay; a reload
            // resets the rest.
            giveConnectionUp()
        }
    }

    /// Offline or in the background: the subscription is closed and the flag released, so the model is no longer
    /// `.ready`. It is `.connecting` until `resume()` has reloaded (a `.failed` phase stays as it is).
    private func giveConnectionUp() {
        if isReloading { connectionLostUnderLoad = true }
        tearDownConnection()
        agentStoppedTyping()
        releaseChat()
        if phase == .ready { phase = .connecting }
    }

    private func handleLifecycle(_ event: HeadlessLifecycleEvent) {
        guard isStarted else { return }
        switch event {
        case .didEnterBackground:
            isSuspended = true
            tasks.cancel("resume")
            giveConnectionUp()
            dataSource.closeChannel()
            channelClosed = true
        case .willEnterForeground:
            guard isSuspended else { return }
            let delay = timing.foregroundDelay
            tasks.set("resume", Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.isStarted else { return }
                self.isSuspended = false
                self.resume()
            })
        }
    }

    /// Reloads from the first page after the network is back or the app returned to the foreground.
    private func resume() {
        guard isStarted, isOnline, !isSuspended else { return }
        tasks.set("reload", Task { @MainActor [weak self] in
            guard let self, self.isStarted else { return }
            // The flag was given back while offline or in the background: claim it again, unless another chat took it.
            guard self.acquireChat() else {
                self.phase = .failed(.unavailable)
                return
            }
            if self.channelClosed {
                self.dataSource.startChannel()
                self.channelClosed = false
            }
            self.phase = .connecting
            do {
                try await self.reload()
                guard self.isStarted, !Task.isCancelled else { return }
                self.phase = .ready
            } catch {
                let mapped = Self.map(error)
                guard self.isStarted, !Task.isCancelled, mapped != .cancelled else { return }
                self.enterFailed(mapped)
            }
        })
    }

    // MARK: - Helpers

    private func emit(_ update: SinchConversationUpdate) {
        broadcaster.send(update, resync: .reset(messages))
    }

    private static var now: Int64 { Int64(Date().timeIntervalSince1970) }

    static func map(_ error: any Error) -> SinchHeadlessError {
        switch error {
        case let error as SinchHeadlessError:
            return error
        case is CancellationError:
            return .cancelled
        case let error as MessageDataSourceError:
            switch error {
            case .noInternetConnection: return .offline
            case .notLoggedIn: return .notLoggedIn
            case .unknownTypeOfMedia: return .unsupportedMedia
            case .unknown(let inner): return .underlying(inner.localizedDescription)
            default: return .underlying(String(describing: error))
            }
        default:
            return .underlying(error.localizedDescription)
        }
    }
}

extension SinchConversation: MessageDataSourceDelegate {
    nonisolated func subscriptionError() {
        Task { @MainActor [weak self] in
            self?.subscriptionDropped()
        }
    }
}
// swiftlint:enable file_length type_body_length
