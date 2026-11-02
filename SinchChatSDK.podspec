Pod::Spec.new do |s|
  s.name             = 'SinchChatSDK'
  s.version          = '2.0.0'
  s.summary          = 'Sinch Chat SDK which supports In App Chat and Push Notifications'
  s.homepage         = 'https://github.com/sinchlabs/sinch-chat-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Sinch' => 'https://sinch.com' }
  # Prebuilt xcframework, built by scripts/build-xcframework.sh and attached to the
  # GitHub release. It is a DYNAMIC framework: it links SinchPushSDK and SwiftProtobuf
  # dynamically, so the app provides them (one protobuf runtime in the process), and
  # gRPC Swift 2 and Kingfisher statically inside the binary. It is built with library
  # evolution, and SinchPushSDK must be too: see the README's post_install hook.
  s.source           = { :http => "https://github.com/sinchlabs/sinch-chat-ios-sdk/releases/download/#{s.version}/SinchChatSDK.xcframework.zip" }
  s.platform         = :ios, '18.0'
  s.swift_version    = '6.0'
  s.vendored_frameworks = 'SinchChatSDK.xcframework'
  # The push SDK is a source pod, not part of the binary. It brings its own
  # SinchPushSDKNotificationExtension pod; this pod depends on the core module only.
  s.dependency 'SinchPushSDK', '~> 1.0'
  # Linked dynamically by the binary, so the app must ship the same runtime.
  s.dependency 'SwiftProtobuf', '~> 1.38'
  s.preserve_paths   = 'LICENSE.md'
  # Notification Service Extension target: do NOT add `pod 'SinchChatSDK'` there, and
  # do not add this pod's binary. Add the extension pod directly:
  #
  #   target 'NotificationServiceExtension' do
  #     pod 'SinchPushSDKNotificationExtension'
  #   end
  #
  # It is Foundation and UserNotifications only, so the extension never loads the
  # chat binary or SwiftProtobuf. There is deliberately no subspec for it: a subspec
  # would inherit `vendored_frameworks` and pull the chat binary into the extension.
end
