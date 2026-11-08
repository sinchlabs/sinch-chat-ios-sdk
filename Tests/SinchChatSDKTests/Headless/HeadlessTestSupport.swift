import Foundation
import XCTest
@testable import SinchChatSDK

// MARK: - Environment

/// Drives connectivity and lifecycle by hand, and records what the model posts.
@MainActor
final class FakeHeadlessEnvironment: HeadlessEnvironment {
    private var connectivity: AsyncStream<Bool>.Continuation?
    private var lifecycle: AsyncStream<HeadlessLifecycleEvent>.Continuation?
    private(set) var posted: [SinchPluginEvent] = []
    private(set) var runningOwner: UUID?
    /// Set to simulate the chat screen (or anything else) holding the "chat is running" flag.
    var externalChatRunning = false

    /// When set, the claim goes to the real flag (`SinchChatSDK.shared._chat`) instead of the booleans above, so a test
    /// can mix the chat screen's writes with the conversation's claims. Connectivity and lifecycle stay under the test's
    /// control either way.
    var chatBackend: SystemHeadlessEnvironment?

    var isChatRunning: Bool { runningOwner != nil || externalChatRunning }

    func connectivityUpdates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        connectivity = continuation
        return stream
    }

    func lifecycleUpdates() -> AsyncStream<HeadlessLifecycleEvent> {
        let (stream, continuation) = AsyncStream<HeadlessLifecycleEvent>.makeStream()
        lifecycle = continuation
        return stream
    }

    func post(_ event: SinchPluginEvent) { posted.append(event) }
    func claimChat(owner: UUID) -> Bool {
        if let chatBackend { return chatBackend.claimChat(owner: owner) }
        if externalChatRunning { return false }
        if let runningOwner, runningOwner != owner { return false }
        runningOwner = owner
        return true
    }

    func releaseChat(owner: UUID) {
        if let chatBackend { return chatBackend.releaseChat(owner: owner) }
        if runningOwner == owner { runningOwner = nil }
    }

    func setOnline(_ online: Bool) { connectivity?.yield(online) }
    func send(_ event: HeadlessLifecycleEvent) { lifecycle?.yield(event) }

    var didCloseChatCount: Int {
        posted.filter { if case .didCloseChat = $0 { true } else { false } }.count
    }
}

// MARK: - Message data source

final class FakeMessageDataSource: MessageDataSource, @unchecked Sendable {
    private let lock = NSLock()

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var topicModel: TopicModel?
    var metadata: SinchMetadataArray = []
    var shouldInitializeConversation = false
    weak var delegate: MessageDataSourceDelegate?

    private var pages: [[Message]] = []
    private var historyFailures = 0
    private var holdBudget = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var eventHook: (@Sendable (EventType) async -> Void)?
    private var _historyTokens: [String?] = []
    private var sendResults: [Result<String, MessageDataSourceError>] = []
    private var continuation: AsyncThrowingStream<Message, Error>.Continuation?
    private var sendHook: (@Sendable (MessageType) async -> Void)?

    private var _sent: [MessageType] = []
    private var _events: [EventType] = []
    private var _uploads = 0
    private var _historyCalls = 0
    private var _subscribeCalls = 0
    private var _closeCalls = 0
    private var _startChannelCalls = 0
    private var _cancelSubscriptionCalls = 0
    private var sendCounter = 0

    var sent: [MessageType] { locked { _sent } }
    var events: [EventType] { locked { _events } }
    var uploads: Int { locked { _uploads } }
    var historyCalls: Int { locked { _historyCalls } }
    var subscribeCalls: Int { locked { _subscribeCalls } }
    var closeCalls: Int { locked { _closeCalls } }
    var startChannelCalls: Int { locked { _startChannelCalls } }
    var cancelSubscriptionCalls: Int { locked { _cancelSubscriptionCalls } }
    /// The page token of every history request, in order (`nil` for a first page).
    var historyTokens: [String?] { locked { _historyTokens } }
    /// History requests that are waiting in the gate (see `holdNextHistoryCalls`).
    var heldHistoryCalls: Int { locked { waiters.count } }

    // MARK: Scripting

    /// Pages are returned oldest page last, like the server pages backwards; each page is chronological. The token of
    /// page `n` is `"n"`; the last page answers with an empty token.
    func setPages(_ newPages: [[Message]]) {
        locked { pages = newPages }
    }

    /// The next `count` history requests are answered with their page, but only after `releaseHistory()`.
    func holdNextHistoryCalls(_ count: Int = 1) { locked { holdBudget = count } }

    /// Lets the oldest `count` held requests answer (all of them by default).
    func releaseHistory(_ count: Int = .max) {
        let released: [CheckedContinuation<Void, Never>] = locked {
            let released = Array(waiters.prefix(count))
            waiters.removeFirst(released.count)
            return released
        }
        released.forEach { $0.resume() }
    }

    func onEvent(_ hook: (@Sendable (EventType) async -> Void)?) { locked { eventHook = hook } }

    func failHistory(times: Int) { locked { historyFailures = times } }
    func queueSendResults(_ results: [Result<String, MessageDataSourceError>]) { locked { sendResults = results } }
    func onSend(_ hook: (@Sendable (MessageType) async -> Void)?) { locked { sendHook = hook } }

    /// Delivers a message on the live subscription.
    func emit(_ message: Message) { _ = locked { continuation }?.yield(message) }

    // MARK: MessageDataSource

    func getMessageHistory() async throws -> [Message] {
        try await getMessageHistoryPage(after: nil).messages
    }

    func getMessageHistoryPage(after token: String?) async throws -> MessageHistoryPage {
        let result: Result<MessageHistoryPage, MessageDataSourceError> = locked {
            _historyCalls += 1
            _historyTokens.append(token)
            if historyFailures > 0 {
                historyFailures -= 1
                return .failure(.unknown(NSError(domain: "fake", code: 1)))
            }
            if token?.isEmpty == true { return .failure(.noMoreMessages) }
            let index = token.flatMap(Int.init) ?? 0
            guard index < pages.count else { return .failure(.noMoreMessages) }
            let next = index + 1 < pages.count ? String(index + 1) : ""
            return .success(MessageHistoryPage(messages: pages[index], nextPageToken: next))
        }
        let shouldHold: Bool = locked {
            guard holdBudget > 0 else { return false }
            holdBudget -= 1
            return true
        }
        if shouldHold {
            await withCheckedContinuation { continuation in locked { waiters.append(continuation) } }
        }
        return try result.get()
    }

    func subscribeForMessages() -> AsyncThrowingStream<Message, Error> {
        let (stream, continuation) = AsyncThrowingStream<Message, Error>.makeStream()
        locked {
            _subscribeCalls += 1
            self.continuation = continuation
        }
        return stream
    }

    func sendMessage(_ message: MessageType) async throws -> String {
        let (hook, result): ((@Sendable (MessageType) async -> Void)?, Result<String, MessageDataSourceError>) = locked {
            _sent.append(message)
            sendCounter += 1
            let result = sendResults.isEmpty ? .success("srv-\(sendCounter)") : sendResults.removeFirst()
            return (sendHook, result)
        }
        await hook?(message)
        return try result.get()
    }

    func sendEvent(_ event: EventType) async throws {
        let hook = locked { eventHook }
        await hook?(event)
        locked { _events.append(event) }
    }

    func uploadMedia(_ media: MediaType) async throws -> String {
        locked { _uploads += 1 }
        return "https://files.example/upload.pdf"
    }

    func uploadMediaViaStream(_ media: MediaType) async throws -> String { try await uploadMedia(media) }
    func sendConversationMetadata(_ metadata: SinchMetadataArray) throws {}

    func cancelSubscription() {
        locked {
            _cancelSubscriptionCalls += 1
            continuation?.finish()
            continuation = nil
        }
    }

    func closeChannel() { locked { _closeCalls += 1 } }
    func startChannel() { locked { _startChannelCalls += 1 } }
    func cancelCalls() {}
    func isSubscribed() -> Bool { locked { continuation != nil } }
    func isFirstPage() -> Bool { true }

    // Completion-handler layer: unused by the headless model.
    func uploadMedia(_ media: MediaType, completion: @escaping @Sendable (Result<String, MessageDataSourceError>) -> Void) {}
    func uploadMediaViaStream(_ media: MediaType, completion: @escaping @Sendable (Result<String, MessageDataSourceError>) -> Void) {}
    func sendMessage(_ message: MessageType, completion: @escaping @Sendable (Result<String, MessageDataSourceError>) -> Void) {}
    func sendEvent(_ event: EventType, completion: @escaping @Sendable (Result<Void, MessageDataSourceError>) -> Void) {}
    func subscribeForMessages(completion: @escaping @Sendable (Result<Message, MessageDataSourceError>) -> Void) {}
    func getMessageHistory(completion: @escaping @Sendable (Result<[Message], MessageDataSourceError>) -> Void) {}
    func sendConversationMetadata(_ metadata: SinchMetadataArray) -> Result<Void, MessageDataSourceError> { .success(()) }
}

// MARK: - Inbox data source

final class FakeInboxDataSource: InboxDataSource, @unchecked Sendable {
    private let lock = NSLock()

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    weak var delegate: InboxDataSourceDelegate?
    private var pages: [[Sinch_Chat_Sdk_V1alpha2_Channel]] = []
    private var holdBudget = 0
    private var failures = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: AsyncThrowingStream<Sinch_Chat_Sdk_V1alpha2_Channel, Error>.Continuation?
    private var _cancelSubscriptionCalls = 0
    private var _getCalls = 0

    var cancelSubscriptionCalls: Int { locked { _cancelSubscriptionCalls } }
    var getCalls: Int { locked { _getCalls } }
    var heldCalls: Int { locked { waiters.count } }

    /// The token of page `n` is `"n"`; the last page answers with an empty token.
    func setPages(_ newPages: [[Sinch_Chat_Sdk_V1alpha2_Channel]]) {
        locked { pages = newPages }
    }

    /// The next `times` page requests fail.
    func failNextCalls(_ times: Int = 1) { locked { failures = times } }

    /// The next `count` page requests are answered with their page, but only after `release()`.
    func holdNextCalls(_ count: Int = 1) { locked { holdBudget = count } }

    func release() {
        let released: [CheckedContinuation<Void, Never>] = locked {
            defer { waiters = [] }
            return waiters
        }
        released.forEach { $0.resume() }
    }

    func emit(_ channel: Sinch_Chat_Sdk_V1alpha2_Channel) { _ = locked { continuation }?.yield(channel) }

    func getChannels() async throws -> [Sinch_Chat_Sdk_V1alpha2_Channel] {
        try await getChannelsPage(after: nil).channels
    }

    func getChannelsPage(after token: String?) async throws -> ChannelsPage {
        let result: Result<ChannelsPage, InboxDataSourceError> = locked {
            _getCalls += 1
            if failures > 0 {
                failures -= 1
                return .failure(.unknown(NSError(domain: "fake", code: 2)))
            }
            if token?.isEmpty == true { return .failure(.noMoreChannels) }
            let index = token.flatMap(Int.init) ?? 0
            guard index < pages.count else { return .failure(.noMoreChannels) }
            let next = index + 1 < pages.count ? String(index + 1) : ""
            return .success(ChannelsPage(channels: pages[index], nextPageToken: next))
        }
        let shouldHold: Bool = locked {
            guard holdBudget > 0 else { return false }
            holdBudget -= 1
            return true
        }
        if shouldHold {
            await withCheckedContinuation { continuation in locked { waiters.append(continuation) } }
        }
        return try result.get()
    }

    func subscribeForChannels() -> AsyncThrowingStream<Sinch_Chat_Sdk_V1alpha2_Channel, Error> {
        let (stream, continuation) = AsyncThrowingStream<Sinch_Chat_Sdk_V1alpha2_Channel, Error>.makeStream()
        locked { self.continuation = continuation }
        return stream
    }

    func cancelSubscription() {
        locked {
            _cancelSubscriptionCalls += 1
            continuation?.finish()
            continuation = nil
        }
    }

    func resetPagination() {}
    func closeChannel() {}
    func startChannel() {}
    func cancelCalls() {}
    func isSubscribed() -> Bool { locked { continuation != nil } }
    func isFirstPage() -> Bool { true }

    func getChannels(completion: @escaping @Sendable (Result<[Sinch_Chat_Sdk_V1alpha2_Channel], InboxDataSourceError>) -> Void) {}
    func subscribeForChannels(completion: @escaping @Sendable (Result<Sinch_Chat_Sdk_V1alpha2_Channel, InboxDataSourceError>) -> Void) {}
}

// MARK: - Builders

enum Fixture {
    static func text(_ id: String, _ text: String, owner: Owner = .incoming(nil), date: Int64 = 1_700_000_000) -> Message {
        Message(entryId: id, owner: owner, body: MessageText(text: text, sendDate: date))
    }

    static func channel(_ id: String, _ name: String) -> Sinch_Chat_Sdk_V1alpha2_Channel {
        var channel = Sinch_Chat_Sdk_V1alpha2_Channel()
        channel.channelID = id
        channel.displayName = name
        return channel
    }

    static let fastTiming = SinchConversation.Timing(typingTimeout: .milliseconds(150), typingSuppression: 0,
                                                     echoGrace: .milliseconds(150), reconnectDelay: .milliseconds(10),
                                                     foregroundDelay: .zero)

    @MainActor
    static func conversation(_ dataSource: FakeMessageDataSource,
                             environment: FakeHeadlessEnvironment,
                             pushPermission: PushNofiticationPermissionHandler? = nil,
                             sendDocumentAsText: Bool = false,
                             isStartedFromInbox: Bool = false,
                             timing: SinchConversation.Timing = fastTiming) -> SinchConversation {
        SinchConversation(dataSource: dataSource, environment: environment, pushPermission: pushPermission,
                          sendDocumentAsText: sendDocumentAsText, isStartedFromInbox: isStartedFromInbox,
                          timing: timing)
    }
}

// MARK: - Shared test helpers

final class AskCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }

    func increment() { lock.lock(); count += 1; lock.unlock() }
}

final class CountingPermissionHandler: PushNofiticationPermissionHandler, @unchecked Sendable {
    let counter: AskCounter

    init(counter: AskCounter) { self.counter = counter }
    func askForPermissions(completion: ((SinchSDKNotificationStatus) -> Void)?) { counter.increment() }
    func checkIfPermissionIsGranted(completion: @escaping (SinchSDKNotificationStatus) -> Void) { completion(.notDetermined) }
}

actor PendingSnapshot {
    private(set) var value: [SinchPendingMessage]?

    func record(_ conversation: SinchConversation) async {
        value = await conversation.pending
    }
}

/// Collects what a conversation's `updates` stream yields, so a test can assert on events after the fact.
@MainActor
final class UpdateRecorder {
    private(set) var events: [SinchConversationUpdate] = []
    private(set) var isFinished = false
    private var task: Task<Void, Never>?

    init(_ conversation: SinchConversation) {
        let stream = conversation.updates
        task = Task { @MainActor [weak self] in
            for await update in stream { self?.events.append(update) }
            self?.isFinished = true
        }
    }

    var removedTempIDs: [String] {
        events.compactMap { if case let .pendingRemoved(tempID) = $0 { tempID } else { nil } }
    }
}

// MARK: - Base class

/// A conversation on a fake data source and a fake environment, stopped after every test.
@MainActor
class ConversationTestCase: XCTestCase {
    var dataSource: FakeMessageDataSource!
    var environment: FakeHeadlessEnvironment!
    var conversation: SinchConversation!

    override func setUp() async throws {
        dataSource = FakeMessageDataSource()
        environment = FakeHeadlessEnvironment()
        conversation = Fixture.conversation(dataSource, environment: environment)
    }

    override func tearDown() async throws {
        conversation.stop()
        conversation = nil
    }

    func startWithHistory(_ pages: [[Message]] = [[Fixture.text("m1", "one"), Fixture.text("m2", "two")]]) async throws {
        dataSource.setPages(pages)
        try await conversation.start()
    }

    func outgoingEcho(id: String, text: String, date: Int64 = 1_800_000_000) -> Message {
        Fixture.text(id, text, owner: .outgoing, date: date)
    }

    /// Takes the device offline and back, which reloads the first page.
    func reconnect() async {
        environment.setOnline(false)
        await waitUntil { !self.conversation.isOnline }
        environment.setOnline(true)
    }
}
