
# Sinch Inbox Documentation

The Sinch Inbox provides functionality to manage and display chat conversations in your iOS application. This guide explains how to use the SinchInbox features effectively.

## Table of Contents
- [Adaptive layout and migration](#adaptive-layout-and-migration)
- [Setup](#setup)
- [Core Features](#core-features)
- [Event Handling](#event-handling)
- [Error Handling](#error-handling)
- [UI Customization](#ui-customization)

## Adaptive layout and migration

`getInboxViewController` now returns an **adaptive inbox** by default (`layout: .automatic`):

- **Regular width** (iPad, wide Split View or Stage Manager windows, an unfolded dual-screen phone): the conversation list is a sidebar and the selected chat opens beside it. A sidebar toggle appears when the window is 600-900pt wide. Rows of the open conversation stay highlighted.
- **Compact width** (iPhone, narrow windows): the list pushes the chat, as before. Resizing the window collapses or expands the layout without recreating the open chat.
- On a dual-screen phone with a vertical hinge the sidebar ends at the hinge and the chat starts after it.

### What changes for existing integrations

| Before | Now |
| --- | --- |
| The returned controller was the list and had to be pushed inside a `UINavigationController`. | The returned controller is a container that draws its own navigation bars. It can be pushed, presented (with or without your navigation controller) or embedded as a child. |
| Your navigation bar was shown above the list. | When the inbox is **pushed** on your `UINavigationController`, your bar is **hidden** while the inbox is visible (and restored when it leaves) so there are not two bars. The swipe-back gesture of your navigation controller keeps working on the list. |
| The back / close button was always on the list's bar. | The same button sits on the sidebar's bar. It pops your stack (pushed), dismisses (presented) or is absent (embedded as a child, or hosted by SwiftUI without `onClose` and not presented modally). |
| `SinchInboxView` wrapped the list in a `UINavigationController` and `makeUIViewController` returned `UINavigationController`. | `SinchInboxView` returns the adaptive container itself (a split view must not be nested in a navigation controller), so its `UIViewControllerType` is now `UIViewController`. Code that referred to `SinchInboxView.UIViewControllerType` as a `UINavigationController`, or reached into the wrapped navigation controller, must be adjusted. |

To keep the previous behaviour exactly, ask for the stack layout:

```swift
let inbox = try SinchChatSDK.shared.chat.inbox.getInboxViewController(layout: .stack)
navigationController?.pushViewController(inbox, animated: true)   // you provide the navigation controller
```

`SinchInboxView(layout: .stack)` does the same in SwiftUI and still wraps the list in a navigation controller.

`layout:` is honoured only by the SDK's own inbox (`SinchChatSDK.shared.chat.inbox`). A custom type conforming to `SinchInbox` ignores it and decides the layout itself.

### SwiftUI hosting

Inside a SwiftUI `NavigationStack` the adaptive inbox would sit under the stack's own bar, giving two bars and no way out of the sidebar. Hide the stack's bar on the destination and give the sidebar a back button with `onClose`:

```swift
.navigationDestination(for: Route.self) { route in
    if route == .inbox {
        SinchInboxView(onClose: { path.removeLast() })
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea()
    }
}
```

Without `onClose` the sidebar shows a close button only when SwiftUI presents the inbox modally (a sheet or full-screen cover); it dismisses the presentation. Pushed on a `NavigationStack`, or embedded in other content, the sidebar has no button without `onClose`, because a SwiftUI host owns that navigation. Pass `onClose` to get a button there (for a sheet, call `dismiss()` from it if you want your own handling).

## Setup

Before using Sinch Inbox, ensure you have initialized the SinchChatSDK and completed user authentication. See the main SDK documentation for these prerequisites.

### SwiftUI

Display the inbox in SwiftUI:

```swift
import SwiftUI
import SinchChatSDK

struct MessageCenterView: View {
    @StateObject private var sinchState = SinchChatSDKState()

    var body: some View {
        SinchInboxView(
            options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true)
        )
        .ignoresSafeArea()
        .task {
            await sinchState.loadInboxChats(options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true))
            sinchState.subscribeToInboxUpdates(options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true))
        }
    }
}
```

Use `SinchChatSDKState` to observe inbox updates:

```swift
sinchState.$lastInboxEvent
    .compactMap { $0 }
    .sink { event in
        switch event {
        case .chatUpdated(let chat):
            print("Chat updated: \(chat.name)")
        case .subcriptionFailed:
            print("Subscription failed")
        }
    }
    .store(in: &cancellables)
```

## Core Features

### 1. Get Inbox View Controller

Display the main inbox interface with a list of conversations:

```swift
do {
    let inboxViewController = try SinchChatSDK.shared.chat.inbox.getInboxViewController(
        uiConfig: nil,                     // Optional UI configuration
        localizationConfig: nil,           // Optional localization
        options: nil                       // Optional chat options
    )

    // Present the inbox view controller
    present(inboxViewController, animated: true)
} catch {
    // Handle error
}
```

### 2. Fetch Inbox Chats

Retrieve a list of conversations:

```swift
SinchChatSDK.shared.chat.inbox.getInboxChats(options: nil) { chats in
    // Handle array of InboxChat objects
    chats.forEach { chat in
        print("Chat name: \(chat.name)")
        print("Last message: \(chat.text)")
        print("Date: \(chat.sendDate)")
    }
}
```

### 3. Subscribe to Inbox Updates

Monitor changes to conversations in real-time:

```swift
// Set up subscription
SinchChatSDK.shared.chat.inbox.subscribeToInboxChatUpdates(options: options)

// Handle updates through the event listener
sinchInbox.chatInboxEventListenerSubject
    .sink { event in
        switch event {
        case .chatUpdated(let chat):
            // Handle updated chat
            print("Chat updated: \(chat.name)")
        case .subcriptionFailed:
            // Handle subscription failure
            print("Subscription failed")
        }
    }
    .store(in: &cancellables)
```

### 4. Open Individual Chats

Open a specific conversation from the inbox:

```swift
do {
    let chatViewController = try SinchChatSDK.shared.chat.inbox.getChatViewController(
        inboxChat: chat,
        uiConfig: nil,                     // Optional UI configuration
        localizationConfig: nil            // Optional localization
    )

    // Present the chat view controller
    present(chatViewController, animated: true)
} catch {
    // Handle error
}
```

## Event Handling

The Sinch Inbox provides real-time updates through the `chatInboxEventListenerSubject`. Events include:

- `chatUpdated`: Triggered when a conversation is updated
- `subcriptionFailed`: Triggered when subscription to updates fails

Example of handling events:

```swift
import Combine

var cancellables = Set<AnyCancellable>()

sinchInbox.chatInboxEventListenerSubject
    .sink { event in
        switch event {
        case .chatUpdated(let chat):
            // Update UI with new chat information
        case .subcriptionFailed:
            // Handle subscription failure, possibly retry
        }
    }
    .store(in: &cancellables)
```

## Error Handling

The Sinch Inbox may throw `SinchInboxSDKError`:

```swift
enum SinchInboxSDKError: Error {
    case unavailable
}
```

Example of error handling:

```swift
do {
    let inboxViewController = try sinchInbox.getInboxViewController()
    // Present view controller
} catch SinchInboxSDKError.unavailable {
    // Handle SDK unavailability
} catch {
    // Handle other errors
}
```

## UI Customization

### Configuration Options

1. UI Configuration (`SinchSDKConfig.UIConfig`):
   - Customize colors, fonts, and layout
   - Modify navigation bar appearance
   - Adjust chat bubble styles

2. Localization (`SinchSDKConfig.LocalizationConfig`):
   - Customize text strings
   - Support multiple languages
   - Modify date formats

Example of customization:

```swift
let uiConfig = SinchSDKConfig.UIConfig(
    // Add UI customization parameters
)

let localizationConfig = SinchSDKConfig.LocalizationConfig(
    // Add localization parameters
)

do {
    let inboxViewController = try SinchChatSDK.shared.chat.inbox.getInboxViewController(
        uiConfig: uiConfig,
        localizationConfig: localizationConfig
    )
    // Present view controller
} catch {
    // Handle error
}
```

## Data Models

### InboxChat

The `InboxChat` model represents a conversation in the inbox:

```swift
public struct InboxChat: Codable {
    public var name: String           // Display name
    public var text: String           // Last message
    public var sendDate: Date         // Last message date
    public var avatarImage: String?   // Avatar image URL
    public var status: String         // Chat status
    public var chatOptions: GetChatViewControllerOptions?
}
```

## Best Practices

1. **Event Handling**:
   - Always maintain a strong reference to your Combine subscribers
   - Handle subscription failures appropriately
   - In SwiftUI, prefer `SinchChatSDKState.subscribeToInboxUpdates(options:)` over manual subject wiring

2. **Error Handling**:
   - Implement proper error handling for all SDK method calls
   - Provide appropriate user feedback for errors

3. **Memory Management**:
   - Cancel subscriptions when they're no longer needed
   - Properly clean up resources in view controller lifecycle methods

4. **UI Updates**:
   - Update UI on the main thread when handling events
   - Consider using loading indicators for async operations
