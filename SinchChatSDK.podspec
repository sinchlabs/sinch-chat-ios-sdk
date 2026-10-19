Pod::Spec.new do |s|
  s.name             = 'SinchChatSDK'
  s.version          = '1.1.0'
  s.summary          = 'Sinch Chat SDK which supports In App Chat and Push Notifications'
  s.homepage         = 'https://github.com/sinchlabs/sinch-chat-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Sinch' => 'https://sinch.com' }
  # Prebuilt xcframework: gRPC Swift 2 is SPM-only, so gRPC, SwiftProtobuf and Kingfisher are linked statically into the binary.
  # Built by scripts/build-xcframework.sh and attached to the GitHub release.
  s.source           = { :http => "https://github.com/sinchlabs/sinch-chat-ios-sdk/releases/download/#{s.version}/SinchChatSDK.xcframework.zip" }
  s.platform         = :ios, '18.0'
  s.swift_version    = '6.0'
  s.vendored_frameworks = 'SinchChatSDK.xcframework'
  s.preserve_paths   = 'LICENSE.md'
end
