Pod::Spec.new do |s|
  s.name             = 'SinchChatSDK'
  s.version          = '0.5.0'
  s.summary          = 'Sinch Chat SDK which supports In App Chat and Push Notifications'
  s.homepage         = 'https://sinch.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Sinch' => '' }
  s.source           = { :git => 'git@git.clxnetworks.net:native/mobile/ios-test-app.git', :tag => s.version.to_s }
  s.ios.deployment_target = '12.0'
  s.swift_version = '5.5'
  s.source_files = 'Sources/SinchChatSDK/**/*.swift'
  s.resource_bundle = { 'SinchChatSDKBundle' => ['Sources/SinchChatSDK/*.{wav,xcassets}', 'Sources/SinchChatSDK/Resources/*.lproj/*.strings'] }
  s.dependency 'gRPC-Swift', '~> 1.10.0'
  s.dependency 'Kingfisher', '~> 7.0'
  s.dependency 'Connectivity', '~> 5.0.0'
end
