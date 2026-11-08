import Foundation

// Entry points of the headless API. They mirror the wiring of `getChatViewController` / `getInboxViewController`:
// the same availability and token checks, the same errors, the same data sources.

public extension SinchChat {

    /// Creates a chat conversation without UI.
    ///
    /// The headless counterpart of ``getChatViewController(uiConfig:localizationConfig:options:)``: the same checks
    /// and the same `options`, but you get an observable model instead of a view controller. Nothing is loaded until
    /// you call ``SinchConversation/start()``.
    ///
    /// ```swift
    /// let conversation = try SinchChatSDK.shared.chat.makeConversation()
    /// try await conversation.start()
    /// try await conversation.send(text: "Hello")
    /// ```
    ///
    /// - Parameter options: Optionally custom chat options (topic, metadata, ...).
    /// - Throws: ``SinchChatSDKError/unavailable`` when the SDK is not initialized or no identity is set, or when a
    ///   chat is already running (see ``isChatAvailable()``). ``SinchConversation/start()`` checks again, because
    ///   another chat can start between creating the model and starting it.
    @MainActor
    func makeConversation(options: GetChatViewControllerOptions? = nil) throws -> SinchConversation {
        guard let chat = self as? DefaultSinchChat else { throw SinchChatSDKError.unavailable }
        return try chat.makeHeadlessConversation(options: options, isStartedFromInbox: false)
    }
}

public extension SinchInbox {

    /// Creates the conversation of an inbox entry, without UI.
    ///
    /// The headless counterpart of ``getChatViewController(inboxChat:uiConfig:localizationConfig:)``. Stopping it keeps
    /// the shared channel open, as leaving a chat opened from the inbox does.
    ///
    /// Unlike `getChatViewController(inboxChat:)`, this does not cancel an inbox subscription. The UI path cancels the
    /// subscription that the SDK itself keeps for its inbox screen and for `subscribeToInboxChatUpdates`, because that
    /// screen goes away while the chat is on top. An inbox model belongs to your code: it uses its own data source, and
    /// its channel stream (`subscribeToChannelsStream`) and the chat stream (`subscribeToStream`) are two separate calls
    /// that share the one HTTP/2 connection, so they do not interfere. Keeping the list live next to an open chat (an
    /// iPad split view, say) is the point of having both. Call ``SinchInboxModel/stop()`` yourself when the list is
    /// not on screen.
    ///
    /// - Throws: ``SinchChatSDKError/unavailable``, as ``SinchChat/makeConversation(options:)``.
    @MainActor
    func makeConversation(inboxChat: InboxChat) throws -> SinchConversation {
        // Like the other entry points: only the SDK's own inbox makes conversations, and it does so on the SDK's chat.
        let chat = SinchChatSDK.shared._chat
        guard let inbox = self as? DefaultSinchInbox, inbox === chat._inbox else { throw SinchChatSDKError.unavailable }
        return try chat.makeHeadlessConversation(options: inboxChat.chatOptions, isStartedFromInbox: true)
    }

    /// Creates the inbox list without UI. Nothing is loaded until you call ``SinchInboxModel/start()``.
    ///
    /// - Parameter options: Optionally custom chat options; they are stored in every ``InboxChat`` of the list.
    /// - Throws: ``SinchChatSDKError/unavailable`` when the SDK is not initialized or no identity is set.
    @MainActor
    func makeInboxModel(options: GetChatViewControllerOptions? = nil) throws -> SinchInboxModel {
        guard let inbox = self as? DefaultSinchInbox else { throw SinchChatSDKError.unavailable }
        return try inbox.makeHeadlessInboxModel(options: options)
    }
}

extension DefaultSinchChat {

    @MainActor
    func makeHeadlessConversation(options: GetChatViewControllerOptions?,
                                  isStartedFromInbox: Bool) throws -> SinchConversation {
        guard isChatAvailable() == .available, let tokenProvider, let region else {
            throw SinchChatSDKError.unavailable
        }
        if apiClient == nil {
            guard let client = Default2APIClient(region: region) else {
                throw SinchChatSDKError.unavailable
            }
            apiClient = client
        }
        guard let apiClient else { throw SinchChatSDKError.unavailable }

        var topicModel: TopicModel?
        if let topicID = options?.topicID {
            topicModel = TopicModel(topicID: topicID)
        }

        let dataSource = DefaultMessageDataSource(
            apiClient: apiClient,
            tokenProvider: tokenProvider,
            topicModel: topicModel,
            metadata: options?.metadata ?? [],
            shouldInitializeConversation: options?.shouldInitializeConversation ?? false,
            sendDocumentAsText: options?.sendDocumentAsTextMessage ?? false)

        // `lastChatOptions` steers push handling of the running chat (topic, addressee): it changes when the
        // conversation starts, not when it is merely created, so creating a second one does not redirect the first.
        return SinchConversation(dataSource: dataSource,
                                 sendDocumentAsText: options?.sendDocumentAsTextMessage ?? false,
                                 isStartedFromInbox: isStartedFromInbox,
                                 willStart: { [weak self] in self?.lastChatOptions = options })
    }
}

extension DefaultSinchInbox {

    @MainActor
    func makeHeadlessInboxModel(options: GetChatViewControllerOptions?) throws -> SinchInboxModel {
        guard let tokenProvider, let region else { throw SinchChatSDKError.unavailable }
        let client: APIClient
        if let apiClient {
            client = apiClient
        } else if let shared = SinchChatSDK.shared.apiClient {
            client = shared
        } else if let created = Default2APIClient(region: region) {
            client = created
        } else {
            throw SinchChatSDKError.unavailable
        }
        apiClient = client

        let dataSource = DefaultInboxDataSource(apiClient: client, tokenProvider: tokenProvider, options: options)
        return SinchInboxModel(dataSource: dataSource, options: options,
                               willStart: { [weak self] in self?.lastChatOptions = options })
    }
}
