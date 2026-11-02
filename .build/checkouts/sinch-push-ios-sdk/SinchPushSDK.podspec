Pod::Spec.new do |s|
  s.name             = 'SinchPushSDK'
  s.version          = '1.0.0'
  s.summary          = 'Sinch push SDK for iOS: APNs, the push relay, delivery reports and in-app message alerts'
  s.description      = <<-DESC
    A standalone push SDK: identity and access token, APNs subscriptions, the
    foreground push relay, delivery reports and in-app message alerts. Built for
    iOS 16 and Swift 6, with SwiftProtobuf as the only dependency.
    The Notification Service Extension is the separate
    SinchPushSDKNotificationExtension pod.
  DESC
  s.homepage         = 'https://github.com/sinchlabs/sinch-push-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Sinch' => 'https://sinch.com' }
  s.source           = { :git => 'https://github.com/sinchlabs/sinch-push-ios-sdk.git', :tag => s.version.to_s }
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.source_files     = 'Sources/SinchPushSDK/**/*.swift'
  # The in-app assets and strings (`InApp/Resources` in Package.swift). The code reads
  # them from `SinchPushSDK.bundle`, which is what `resource_bundles` produces.
  s.resource_bundles = {
    'SinchPushSDK' => [
      'Sources/SinchPushSDK/InApp/Resources/**/*.{xcassets,strings}'
    ]
  }
  s.frameworks       = 'Foundation', 'UIKit', 'UserNotifications'
  # Required for the `package` symbols the report code shares with the extension and
  # for the `@_spi(SinchChat)` API the prebuilt SinchChatSDK binary calls. The exact
  # version, because the two pods are released together and share those symbols.
  s.dependency 'SinchPushSDKNotificationExtension', s.version.to_s
  s.dependency 'SwiftProtobuf', '~> 1.28'
  # The prebuilt SinchChatSDK binary is compiled against a resilient push module, so
  # the app has to build one too. See SinchChatSDK 2.0.0 and the README.
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name SinchPushSDK',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES'
  }
end
