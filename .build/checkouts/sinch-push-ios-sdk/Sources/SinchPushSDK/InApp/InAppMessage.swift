import Foundation

/// An in-app alert delivered by Sinch Push, either in an APNs payload or in the
/// metadata of a relay (WebSocket) message.
///
/// The SDK renders it with `InAppMessages` unless `InAppMessageDelegate`
/// takes over. The model is deliberately independent of the chat SDK: only the
/// six layouts the push channel sends are represented.
public struct InAppMessage: Sendable, Equatable {

    /// The layout and content of the alert.
    public var body: Body

    public init(body: Body) {
        self.body = body
    }
}

extension InAppMessage {

    /// The rendered layouts.
    public enum Body: Sendable, Equatable {
        /// A text-only alert.
        case text(text: String)
        /// A full-bleed image alert. `url` is the media peer, not validated: an
        /// unparseable value only means the image does not load.
        case media(url: String)
        /// A map alert with a title and a button that opens a maps app.
        case location(InAppLocation)
        /// Text with a stack of buttons.
        case choices(text: String, choices: [InAppChoice])
        /// A card: image, title, description and buttons.
        case card(InAppCard)
        /// Paged cards with an optional set of choices shared by the carousel.
        case carousel(cards: [InAppCard], choices: [InAppChoice])
    }
}

/// A card inside a `card` or `carousel` alert.
public struct InAppCard: Sendable, Equatable {

    public var title: String
    public var description: String
    public var media: String
    public var choices: [InAppChoice]

    public init(title: String, description: String, media: String, choices: [InAppChoice]) {
        self.title = title
        self.description = description
        self.media = media
        self.choices = choices
    }
}

/// A physical location, used by the `location` alert and the `location` choice.
public struct InAppLocation: Sendable, Equatable {

    public var title: String
    public var label: String
    public var latitude: Double
    public var longitude: Double

    public init(title: String, label: String, latitude: Double, longitude: Double) {
        self.title = title
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A button and the action it performs.
public struct InAppChoice: Sendable, Equatable {

    public var title: String
    public var action: InAppChoiceAction

    public init(title: String, action: InAppChoiceAction) {
        self.title = title
        self.action = action
    }
}

/// What tapping a choice does.
///
/// `text` is the postback action: the SDK has no reply endpoint, so it hands the
/// choice to `InAppMessageDelegate.didTapAction(_:in:)` and does nothing else.
public enum InAppChoiceAction: Sendable, Equatable {
    /// A postback, reported to the delegate.
    case text(postbackData: String)
    /// Opens the URL in `SFSafariViewController`. Only `http` and `https` are accepted.
    case url(String)
    /// Opens `tel:`.
    case call(phoneNumber: String)
    /// Offers to open the location in Apple or Google Maps.
    case location(InAppLocation)
}
