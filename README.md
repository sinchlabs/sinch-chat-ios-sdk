
# iOS Sinch SDK - Getting Started


This is documentation how to easily implement our SDK for chat and for push features.

  

# Requirements

  

- Xcode 14+

- Swift package manager (********iOS 13+********)

  

# Installation

  

### Swift Package Manager:

  

1. Copy link to this repository `https://github.com/sinchlabs/sinch-chat-ios-sdk`

2. Paste into xCode SPM and login to your github account using login + github personal token.

  

# First steps

  

1. Initialize SDK as soon as application is starting.

2. SetIdentity as soon as you can authenticate the user using your internal ********UserID******** and sign it using algorithm on ********the backend side.******** (You can sign it on mobile but it is ********NOT RECOMMENDED********) ← this method can be called multiple times.

3. Setup push notifications.

4. Show chat.



## Initialize


```swift

SinchChatSDK.shared.initialize()

```

As soon as possible it means the best place to do that is AppDelegate in:

```swift

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool

```

********Example:********

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

- Config ID (leave "" if you don't have it)

- _*___(Optional)__* Token secret

  

## Set identity

The second step is that we need to authorize user so we need you to call us this method as soon as you can authorize the user. You can call this method as many times as you want:

  

```swift


func setIdentity(with config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity, completion: ((Result<Void, SinchSDKIdentityError>) -> Void)? = nil)


```

  

********Example:********

  

```swift
let config = SinchSDKConfig.AppConfig(
        clientID: {{ client_id }}, 
        projectID: {{ project_id }}, 
        configID: {{ config_id }}, // If you don't have it, leave empty string "" 
        region: .EU1
)
let currentIdentityType: SinchSDKIdentity = .anonymous
 

SinchChatSDK.shared.setIdentity(with: config, identity: currentIdentityType) { result in

switch result {

case .success:

// SDK is authenticated successfully.

case .failure(let error):

// SDK cannot be initizalized so you can't use any functionality :/

}
}

```

### Types of Sinch SDK Identity

There are two types of identity:
    
```swift 

public enum SinchSDKIdentity: Codable, Equatable {
/// Creates anonymous session with random user identifier.
case anonymous
/// Creates session with specific user identifier.
case selfSigned(userId: String, secret: String)
}

```
  
In anonymous sessions, we generate a unique User Identifier to identify the user for your projectID and clientID.    
If you have a self-signed user id, **you** can specify it to be used in the scope of the projectID, clientID and configID.    
This means you can send push notifications or start a live chat using the identifier assigned in your database.  


Example:
---
- ********Anonymous session********  
  
When you call setIdentity method with `.anonymous` identity we're generating random user, for example: 01GYC7B5TR5QR1NE2NRQDPGP0X. Until [removeIdentity](#remove-identity) is called, we're using this user for instantiating chat and push.  
 
********Example:********
 
```swift

import SinchChatSDK
//...
let currentIdentityType: SinchSDKIdentity = .anonymous

SinchChatSDK.shared.setIdentity(with: {{config}}, identity: .anonymous) { result in }

```
         
- ********Signed session********  

In order to create a selfSign identity for user, you need to provide a unique identifier for that user. You can either use some id, phone number, email address, etc…  
********One benefit of using a self-signed session, as opposed to anonymous, is that you can retain your chat history when you remove and then set the same identity.********  

How to login using your identifier?

********Example:********

```swift

import SinchChatSDK
//...
let userID = "{your_unique_user_id}" // for example: "user123"

let signedUserID: String = userID.hmac(algorithm: CryptoAlgorithm.SHA512, key: {your_secret})

SinchChatSDK.shared.setIdentity(with: {{config}}, identity: .selfSigned(userId: userID, secret: signedUserID)) { result in }

```

<aside>

💡 ********your_secret******** is Secret Key provided by you on Sinch Dashboard when you created Sinch Live Chat app. 

</aside>


And now you can use SDK functionalities like chat or push.

## Remove identity

This method is logging out user. It removes token and other user data from the app. After calling this method, you need to call setIdentity again to use the chat and get push notifications. 

  
********Example:********
  
```swift

SinchChatSDK.shared.removeIdentity { result in
    
switch result {
case .success():
debugPrint("remove identity success")

case .failure(_):
debugPrint("remove identity error")
}
}

```

## Info.plist permissions

  

### Push notifications permission 

- Capability → `Push Notifications`

- Capability → `background modes` → `Remote notifications` + explanation in info.plist:


********Example:********

```swift

<dict>

<key>UIBackgroundModes</key>

<array>

<string>remote-notification</string>

</array>

</dict>

  
```

### Other permissions

If you keep [enabled](#disable-some-of-the-features) the option to send voice messages, you will need to add the `NSMicrophoneUsageDescription` permission.  
 Likewise, if you keep [enabled](#disable-some-of-the-features) the Share Location option, you may also need to add location permissions `NSLocationAlwaysAndWhenInUseUsageDescription` and `NSLocationWhenInUseUsageDescription` based on your use case.

********Example:********

```swift

<dict>

<key>NSMicrophoneUsageDescription</key>
<string>Enabling microphone access lets you send voice messages in the chat.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Enabling location services will allow you to share your location with others through the chat.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Enabling location services will allow you to share your location with others through the chat.</string>

</dict>

  
```

## Privacy manifest files

In SDK source code there is `PrivacyInfo.xcprivacy` that describe the data SDK collects and the reasons required APIs it uses. 

See more at https://developer.apple.com/documentation/bundleresources/privacy_manifest_files

### Describing data use in privacy manifests

Record the categories of data that your app or third-party SDK collects about the person using the app, and the reasons it collects the data. 

If you keep [enabled](#disable-some-of-the-features) the option to send voice messages, you will ********need to add******** add the `NSPrivacyCollectedDataTypeAudioData` data type to your `PrivacyInfo` file.  
Likewise, if you keep [enabled](#disable-some-of-the-features) the Share Location option, you may also ********need to add******** `NSPrivacyCollectedDataTypePreciseLocation` data type to your `PrivacyInfo` file. 
If you keep [enabled](#disable-some-of-the-features) the option to send photo or video messages, you will ********need to add******** the `NSPrivacyCollectedDataTypePhotosorVideos` data type to your `PrivacyInfo` file.

See more at  https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_data_use_in_privacy_manifests

********Example:********


```swift

    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeAudioData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>User can send voice message to the other user using chat.</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePhotosorVideos</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>User can send his photos or videos to the other user using chat.</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePreciseLocation</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>User can send his location to the other using chat.</string>
            </array>
        </dict>
    </array>

```

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

  

## Show chat


********Before showing the chat make sure you have initialised this SDK.********

   

### Present chat view controller modally
  
  
    
```swift

do {
     
let options = GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true)
let chatViewController = try SinchChatSDK.shared.chat.getChatViewController(uiConfig: .defaultValue,
                                                                            localizationConfig: .defaultValue,
                                                                            options: options)
                    
let navigationController = UINavigationController(rootViewController: chatViewController)
navigationController.modalPresentationStyle = .fullScreen
self?.present(navigationController, animated: true, completion: nil)
    
} catch {
// all errors are related with bad configuration. You can check if chat is available using `isChatAvailable` method.


}}

```

### Programmatically push chat view controller onto the current navigation stack
  
  
    
```swift

do {
 
let options = GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true)
let chatViewController = try SinchChatSDK.shared.chat.getChatViewController(uiConfig: .defaultValue,
                                                                        localizationConfig: .defaultValue,
                                                                        options: options)
                
self.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
self.navigationController?.pushViewController(viewControler, animated: true)

} catch {
// all errors are related with bad configuration. You can check if chat is available using `isChatAvailable` method.

}}

```

### Chat options

If you need to create a chat that is connected to, for example, some order, you can use topicID.   
If you need to pass metadata to chat you can use the metadata parameter.  
If the conversation should start when the user enters the chat set shouldInitializeConversation to true.  
If you want to send document files as text messages and not as media messages set sendDocumentAsTextMessage to true.  



```swift

let options = GetChatViewControllerOptions(topicID: "{topicID}",
                                           metadata: [],
                                           shouldInitializeConversation: true,
                                           sendDocumentAsTextMessage: true)  
  
  

```



### Update Localization Configuration

It is possible to customise the text for each UI element within the SDK. We’re currently supporting the English language only, if you want to have other languages as well then override the `localizationConfig` parameter.


********Example:********


```swift


var localizationConfig = SinchSDKConfig.LocalizationConfig.defaultValue
localizationConfig.disabledChatMessageText = NSLocalizedString("errorMessage", comment: "")
                  
let viewControler = try SinchChatSDK.shared.chat.getChatViewController(uiConfig: .defaultValue,
                                                                       localizationConfig: localizationConfig)
  
  
```

### Update UI Configuration


It is possible to customise the all colors and images within the SDK.


********Example:********

```swift


var uiConfig = SinchSDKConfig.UIConfig.defaultValue
uiConfig.navigationBarColor = .white 
uiConfig.navigationBarTitleColor = UIColor(red: 0.0, green: 43.0/256.0, blue: 227.0/256.0, alpha: 1.0)
uiConfig.backIcon =  UIImage(named: "backIcon")
uiConfig.closeIcon =  UIImage(named: "closeIcon")

                  
let viewControler = try SinchChatSDK.shared.chat.getChatViewController(uiConfig: uiConfig,
                                                                       localizationConfig: .defaultValue)
  
  
```
### Override media store

You can upload media to your repository and provide url string 

********Example:********


```swift

        SinchChatSDK.shared.overrideMediaStore =  {(file, completion) in
            
            // upload media to your media store and return back URL string
            
            return completion(.success("{url string}"))
        }

```


### Disable sending messages


You can disable the sending of any type of message.  

********Example:********

```swift

SinchChatSDK.shared.chat.advanced.disableSendingMessages()

var localizationConfig = SinchSDKConfig.LocalizationConfig.defaultValue
localizationConfig.disabledChatMessageText = "Sending messages is disabled"
                  
let viewControler = try SinchChatSDK.shared.chat.getChatViewController(uiConfig: .defaultValue,
                                                                       localizationConfig: localizationConfig)

```

### Enable sending messages

********Example:********

```swift

SinchChatSDK.shared.chat.advanced.enableSendingMessages()


```

### Disable some of the features

It is possible to disable some of the features in the chat. A button that is in the Input view will disappear if all features connected with it are disabled. For example, if you disable sending voice messages, the button responsible for it will disappear. 

********List of features that is possible to disable:********


```swift

public enum SinchEnabledFeatures {
case sendImageMessageFromGallery
case sendVideoMessageFromGallery
case sendVoiceMessage
case sendLocationSharingMessage
case sendImageFromCamera
case sendVideoMessageFromCamera
case sendDocuments

}

```

********Example:********


```swift

SinchChatSDK.shared.disabledFeatures = [.sendVoiceMessage,
                                        .sendVideoMessageFromCamera,
                                        .sendVideoMessageFromGallery,
                                        ]

```

# Push

  

### APNS certificate

  

To use ********push notifications******** with this SDK you have to provide ********APNS Key******** and upload it to out Sinch Panel.


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
