Pod::Spec.new do |s|
  s.name             = 'SinchChatSDK'
  s.version          = '0.11.8'
  s.summary          = 'Sinch Chat SDK which supports In App Chat and Push Notifications'
  s.homepage         = 'https://sinch.com'
  s.license          = { :type => 'MIT', :file => 'README.md' }
  s.author           = { 'Sinch' => '' }
  s.source           = { :git => 'https://github.com/sinchlabs/sinch-chat-ios-sdk.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.5'
  s.source_files = 'Sources/SinchChatSDK/**/*.swift'
  s.resource_bundle = { 'SinchChatSdk-SinchChatSDK_SinchChatSDK' => [
    'Sources/SinchChatSDK/Assets.xcassets',
    'Sources/SinchChatSDK/Resources/*.lproj/*.strings',
  ]}
  s.dependency 'gRPC-Swift', '~> 1.8.0'
  s.dependency 'Kingfisher', '~> 7.10.0'
end

