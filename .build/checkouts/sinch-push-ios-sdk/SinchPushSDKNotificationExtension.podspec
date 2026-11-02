Pod::Spec.new do |s|
  s.name             = 'SinchPushSDKNotificationExtension'
  s.version          = '1.1.0'
  s.summary          = 'Sinch push Notification Service Extension: Foundation and UserNotifications only'
  s.description      = <<-DESC
    The Notification Service Extension part of SinchPushSDK. Add this pod to the
    extension target only: `SinchPushNotificationExtension.didReceive(_:appGroup:)`
    reports the delivery of a Sinch push from the extension.
    It has no UIKit and no third-party dependency, so a Notification Service
    Extension stays inside the iOS memory limit.
  DESC
  s.homepage         = 'https://github.com/sinchlabs/sinch-push-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Sinch' => 'https://sinch.com' }
  s.source           = { :git => 'https://github.com/sinchlabs/sinch-push-ios-sdk.git', :tag => s.version.to_s }
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.source_files     = 'Sources/SinchPushSDKNotificationExtension/**/*.swift'
  s.frameworks       = 'Foundation', 'UserNotifications'
  # CocoaPods compiles every subspec into one module, so the extension is a pod of
  # its own and shares the `package` symbols of SinchPushSDK. Both podspecs must pass
  # the same package name, otherwise the package-scoped API does not line up.
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name SinchPushSDK',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES'
  }
end
