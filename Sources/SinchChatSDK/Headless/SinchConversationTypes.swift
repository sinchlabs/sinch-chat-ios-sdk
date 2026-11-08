import Foundation

// Public value types of the headless chat API. Foundation only: nothing here mentions UIKit or SwiftUI.

/// Why a call on a headless model (``SinchConversation`` or ``SinchInboxModel``) failed.
///
/// This enum may gain cases in minor releases. Include a `default:` in every `switch` over it, or the project stops
/// compiling when you update the SDK.
public enum SinchHeadlessError: Error, Equatable, Hashable, Sendable {
    /// The model has not been started (or was stopped, or is not ready for the call). Call
    /// ``SinchConversation/start()`` (or ``SinchInboxModel/start()``) first.
    case notStarted
    /// The device is offline (or the app is in the background): nothing was sent, or the load was interrupted by it.
    /// A model that is started reloads by itself when the connection is back.
    case offline
    /// There is no stored identity, or its token cannot sign the request.
    case notLoggedIn
    /// The media could not be read or converted for upload.
    case unsupportedMedia
    /// ``SinchConversation/retry(_:)`` was given an id that is not a failed pending message.
    case unknownPendingMessage
    /// The call was superseded (for example by a reconnect or ``SinchConversation/stop()``) before it finished.
    case cancelled
    /// Another chat (the chat screen or another conversation) is running: only one chat can run at a time.
    case unavailable
    /// Any other failure, with the underlying description.
    case underlying(String)
}

/// An outgoing message that the server has not confirmed yet.
///
/// Equality and hashing use ``tempID`` and ``status`` only: ``body`` is a protocol existential, and an upload that
/// swaps a local file URL for the uploaded one does not make it another message. Compare the bodies yourself when
/// you need to.
public struct SinchPendingMessage: Identifiable, Sendable, Equatable, Hashable {
    /// This enum may gain cases in minor releases. Include a `default:` in every `switch` over it.
    public enum Status: Equatable, Hashable, Sendable {
        /// Being uploaded or sent.
        case sending
        /// The send failed. Call ``SinchConversation/retry(_:)`` to try again.
        case failed
    }

    /// Stable local id, also the argument of ``SinchConversation/retry(_:)``.
    public let tempID: String
    public var id: String { tempID }
    public internal(set) var body: any MessageBody
    public internal(set) var status: Status
    /// The last failure while ``status`` is `.failed`.
    public internal(set) var error: SinchHeadlessError?
    public let createdAt: Date

    public static func == (lhs: SinchPendingMessage, rhs: SinchPendingMessage) -> Bool {
        lhs.tempID == rhs.tempID && lhs.status == rhs.status
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(tempID)
        hasher.combine(status)
    }
}

/// A media attachment to send. Data or file URLs only, so no UIKit type is needed.
///
/// This enum may gain cases in minor releases (another kind of attachment). Include a `default:` in every `switch`
/// over it.
public enum SinchMedia: Sendable {
    /// Encoded image data (JPEG, PNG, HEIC, ...). It is re-encoded as JPEG for upload, like the chat screen does.
    case image(Data)
    /// A video file.
    case video(URL)
    /// An audio file.
    case audio(URL)
    /// Any other file. Its extension picks the document type (`pdf`, `docx`, ...).
    case file(URL)
}

/// A change to ``SinchConversation/messages`` or ``SinchConversation/pending``, for UIKit diffing.
///
/// SwiftUI does not need this: observe the model's properties instead.
///
/// Only changes to the two lists are events. ``SinchConversation/phase``, ``SinchConversation/isAgentTyping``,
/// ``SinchConversation/isOnline``, ``SinchConversation/isLoadingHistory`` and ``SinchConversation/hasMoreHistory``
/// are observable properties only; UIKit code reads them when it needs them (or observes them with
/// `withObservationTracking`).
///
/// This enum may gain cases in minor releases. Include a `default:` in every `switch` over it (a good default is to
/// rebuild your snapshot from ``SinchConversation/messages`` and ``SinchConversation/pending``).
public enum SinchConversationUpdate: Sendable {
    /// ``SinchConversation/messages`` was replaced: the first page after ``SinchConversation/start()`` or a reconnect.
    /// It is also sent to a stream that fell more than 256 events behind: rebuild from ``SinchConversation/messages``
    /// and ``SinchConversation/pending`` then.
    case reset([Message])
    /// Older messages were inserted at the front by ``SinchConversation/loadMore()``.
    case prepended([Message])
    /// A new message arrived at the end.
    case appended(Message)
    /// A pending message was added.
    case pendingAdded(SinchPendingMessage)
    /// A pending message changed status (sending to failed, or back to sending on retry).
    case pendingUpdated(SinchPendingMessage)
    /// A pending message was confirmed and its entry with `tempID` was removed. `message` was appended to
    /// ``SinchConversation/messages``, unless the list already contained it (the history loaded it before the
    /// confirmation arrived): then only the pending entry went away.
    case resolved(tempID: String, message: Message)
    /// A pending message went away without being confirmed here: ``SinchConversation/discard(_:)`` removed it, or a
    /// history page that was loaded meanwhile already contains it (a ``reset(_:)`` or ``prepended(_:)`` follows), or
    /// ``SinchConversation/stop()`` dropped a message the server had already accepted.
    case pendingRemoved(tempID: String)
}

// MARK: - Message content

/// A button of a choice or card message.
///
/// This enum may gain cases in minor releases (another kind of action). Include a `default:` in every `switch` over
/// it; ``SinchConversation/sendChoice(_:)`` answers ``reply(text:postback:messageID:)`` only.
public enum SinchChoice: Sendable, Equatable, Hashable {
    /// A quick reply. Send it back with ``SinchConversation/sendChoice(_:)``.
    case reply(text: String, postback: String, messageID: String)
    /// Opens a URL. Opening it is up to the host app.
    case url(text: String, url: String)
    /// Starts a phone call. Dialing is up to the host app.
    case call(text: String, phoneNumber: String)
    /// Shows a place. Showing it is up to the host app.
    case location(text: String, label: String, latitude: Double, longitude: Double)
}

/// A card of a card or carousel message.
public struct SinchCard: Sendable, Equatable, Hashable {
    public let title: String
    public let description: String
    public let mediaURL: String
    public let choices: [SinchChoice]
}

/// What a ``Message`` shows, without casting `message.body` to the concrete body types.
///
/// This enum may gain cases in minor releases (every new kind of message the server sends). Include a `default:` in
/// every `switch` over it, and show a placeholder for what you do not know, as for ``unsupported``.
public enum SinchMessageContent: Sendable, Equatable {
    case text(String)
    case media(url: String, type: TypeMessageMedia?)
    /// A text with an attachment.
    case mediaText(text: String, url: String)
    case voice(url: String)
    case location(title: String, label: String, latitude: Double, longitude: Double)
    case choices(text: String, choices: [SinchChoice])
    case card(SinchCard)
    case carousel([SinchCard])
    /// A system line such as "Agent joined the conversation".
    case event(text: String)
    case unsupported
    /// A body type added by a plugin.
    case custom
}

public extension Message {
    /// The content of the message as an enum, including the choice, card and carousel bodies that are internal to the
    /// SDK. ``SinchMessageContent`` may gain cases in minor releases: switch over it with a `default:`.
    var content: SinchMessageContent {
        switch body {
        case let text as MessageText:
            return .text(text.text)
        case let media as MessageMedia:
            return .media(url: media.url, type: media.type)
        case let mediaText as MessageMediaText:
            return .mediaText(text: mediaText.text, url: mediaText.url)
        case let voice as MessageVoice:
            return .voice(url: voice.url)
        case let location as MessageLocation:
            return .location(title: location.title, label: location.label,
                             latitude: location.latitude, longitude: location.longitude)
        case let choices as MessageChoices:
            return .choices(text: choices.text, choices: choices.choices.map(SinchChoice.init))
        case let card as MessageCard:
            return .card(SinchCard(card))
        case let carousel as MessageCarousel:
            return .carousel(carousel.cards.map(SinchCard.init))
        case let event as MessageEvent:
            return .event(text: Self.eventText(event))
        case is MessageUnsupported:
            return .unsupported
        default:
            return .custom
        }
    }

    /// The line of a system event. A fallback event carries its raw payload instead of a text; typing events have none.
    private static func eventText(_ event: MessageEvent) -> String {
        if case let .fallbackMessage(payload) = event.type { return payload }
        return event.text ?? ""
    }
}

extension SinchChoice {
    init(_ choice: ChoiceMessageType) {
        switch choice {
        case .textMessage(let text):
            self = .reply(text: text.text, postback: text.postback, messageID: text.entryID)
        case .urlMessage(let url):
            self = .url(text: url.text, url: url.url)
        case .callMessage(let call):
            self = .call(text: call.text, phoneNumber: call.phoneNumber)
        case .locationMessage(let location):
            self = .location(text: location.text, label: location.label,
                             latitude: location.latitude, longitude: location.longitude)
        }
    }
}

extension SinchCard {
    init(_ card: MessageCard) {
        self.init(title: card.title, description: card.description, mediaURL: card.url,
                  choices: card.choices.map(SinchChoice.init))
    }
}
