
# iOS Sinch SDK - Getting Started

  

  

This is documentation how to easily implement our SDK for chat and for push features.

  

# Requirements

  

- Xcode 13+

- Swift package manager (********iOS 11+********)

  

# Installation

  

### Swift Package Manager:

  

1. Copy link to this repository `https://github.com/sinchlabs/sinch-chat-ios-sdk`

2. Paste into xCode SPM and login to your github account using login + github personal token.

  

# First steps

  

1. Initialize SDK as soon as application is starting.

  

2. SetIdentity as soon as you can authenticate the user using your internal ********UserID******** and sign it using algorithm on ********the backend side.******** (You can sign it on mobile but it is ********NOT RECOMMENDED********) ← this method can be called multiple times.

3. Setup push notifications.

4. Show chat.

  

### Info.plist permissions

We need two permissions in info.plist:

  

- Push notifications permission and microphone access:

- Capability → `Push Notifications`

- Capability → `background modes` → `Remote notifications` + explanation in info.plist:

```swift

<dict>

<key>UIBackgroundModes</key>

<array>

<string>remote-notification</string>

</array>

<key>NSMicrophoneUsageDescription</key>

<string>Need microphone access for sending voice messages</string>

</dict>

  

```

## Initialize

  

```swift

SinchChatSDK.shared.initialize()

```

As soon as possible it means the best place to do that is AppDelegate in:

```swift

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool

```

Example:

```swift

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

SinchChatSDK.shared.initialize()

return true

}

  

```

### Config

We need to have configuration for chat which we’re providing to you it means you need:

- Region

  

- Project ID

  

- Client ID

  

- _*___(Optional)__* Token secret

  

## Set identity

The second step is that we need to authorize user so we need you to call us this method as soon as you can authorize the user. You can call this method as many times as you want:

  

```swift

  

func setIdentity(with config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity, completion: ((Result<Void, SinchSDKIdentityError>) -> Void)? = nil)

  

```

  

Example:

  

```swift

  

SinchChatSDK.shared.setIdentity(with: currentEnvironment.toSinchConfig, identity: currentIdentityType) { result in

switch result {

case .success:

// SDK is authenticated successfully.

case .failure(let error):

// SDK cannot be initizalized so you can't use any functionality :/

}

}

```

### Signing custom user ID
In case of anonymous session we're generating unique User Identifier to have unique identifier of user in scope of your projectID and clientID.

In case of signed user id **you** can specify user id so we will use it in scope of projectID and clientID.
What does it mean? You can send push notification or start live chat which identifier which is assigned in your database.

Example:
---
- Anonymous session
	We're generating random user id so it will be: 01GYC7B5TR5QR1NE2NRQDPGP0X
	If you want to start chat or send push notification you need to save this our user id in your database and use it in our system if you want to do some interaction.
- Signed session
	In your database / system you have this user saved under identifier 543234 or phone number 2124567890.
	You can login to our SDK by using 543234 identifier or phone number.
	You can send push / start chat using identifier or phone number instead of our identifier.

How to login using your identifier?

Example:
```
import SinchChatSDK
//...
let userID = "{your_unique_id}"
let signedUserID: String = userID.hmac(algorithm: CryptoAlgorithm.SHA512, key: {your_secret})

SinchChatSDK.shared.setIdentity(with: {{config}}, identity: .selfSigned(userId: userID, secret: signedUserID))
```

And now you can use SDK functionalities like chat or push.

# Chat

  

  

## Check chat availability

  

To check if the chat is available for user you should use method:

```swift

public enum SinchSDKChatAvailability {

/// The Chat is ready to user.

case available

/// The Chat is not initialized

/// Tip: use initialize method to initialize chat.

case uninitialized

  

/// The chat is not authorized

/// Tip: User setIdentity method to authorize the client.

case authorizationNeeded

  

/// The chat is opened

/// You cannot run two chats at once.

case currentlyRunning

}

  

func isChatAvailable() -> SinchSDKChatAvailability

  

```

  

## Showing chat

  

  

********Before showing the chat make sure you have initialised this SDK.********

  

You have couple of options how you can show chat.

You can use your own UINavigationController to show our chat.

You can just present our chat using standard transitions or your custom ones.

To do that there is method in `SinchChatSDK.shared.chat.*`

  

<aside>

💡 If you will pass `navigationController == nil` then we will create our own because we need it anyway.

</aside>

  

```swift

func getChatViewController(navigationController: UINavigationController?,

uiConfig: SinchSDKConfig.UIConfig?,

localizationConfig: SinchSDKConfig.LocalizationConfig?) throws -> UIViewController

```

<aside>

💡 We’re returning `UIViewController` which you have to present in ********your own******** way.

</aside>

<aside>

💡 We’re currently supporting English language only, if you want to have other languages as well then override `localizationConfig` parameter.

</aside>

********Example:********

  

```swift

do {

let chatViewController = try SinchChatSDK.shared.chat.getChatViewController()

chatViewController.modalPresentationStyle = .fullScreen

present(chatViewController, animated: true, completion: nil)

} catch {

// all errors are related with bad configuration. You can check if chat is available using `isChatAvailable` method.

}

```

# Push

  

### APNS certificate

  

To use ********push notifications******** with this SDK you have to provide ********APNS Key******** and upload it to out Sinch Panel.

<aside>

💡 Push notification works only on ********real device.********

</aside>

  

### Xcode Capabilities

  

  

Make sure you’ve checked `Remove notifications` capability in `Background Modes` in your target configuration in tab `Signing & Capabilities` and `Push Notifications` .

  

### Methods in AppDelegate.swift or AppDelegate.m:

  

```swift

func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {

SinchChatSDK.shared.push.sendDeviceToken(deviceToken)

}

  

```

<aside>

💡 Make sure you’ve added `UNUserNotificationCenterDelegate` to AppDelegate definition or to you own class.

</aside>

  

```swift

func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {

  

if SinchChatSDK.shared.push.handleNotificationResponse(response) {

// this is our notification and it is handled by SinchChatSDK

}

  

completionHandler()

}

```

  

```swift

func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {

  

if let presentationOptions = SinchChatSDK.shared.push.handleWillPresentNotification(notification) {

completionHandler(presentationOptions)

return

}

completionHandler([])

}

  

```

  

### Additional methods

  

Those methods are ********optional******** and they are only ********helpers for you******** if you want to ask for notifications in other places then after starting the chat. Please don’t ask user for notification at application start. ********It is a bad practice.******** Ask when you need it.

  

Possibility to check push permission using our method:

  

```swift

SinchChatSDK.shared.push.checkPushPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void)

  

// OR iOS 13+ with Combine

func checkPushPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never>

```

Possibility to ask for notifications permission:

```swift

func askNotificationPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void)

  

// OR iOS 13+ with Combine

func askNotificationPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never>

```