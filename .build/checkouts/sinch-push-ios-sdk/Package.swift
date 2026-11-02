// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SinchPushSDK",
    defaultLocalization: "en",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SinchPushSDK", targets: ["SinchPushSDK"]),
        // For a Notification Service Extension target only: no UIKit, no third-party dependencies.
        .library(name: "SinchPushSDKNotificationExtension", targets: ["SinchPushSDKNotificationExtension"])
    ],
    dependencies: [
        // The only dependency: the protobuf message runtime. No gRPC runtime, no NIO.
        // `traits: []` keeps the default traits off, so this package and grpc-swift-protobuf
        // (in the chat package) can coexist in one dependency graph (phase 0, spike D).
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0", traits: [])
    ],
    targets: [
        // Shared by the app and the Notification Service Extension: Foundation, UserNotifications and os only.
        .target(name: "SinchPushSDKNotificationExtension"),
        .target(
            name: "SinchPushSDK",
            dependencies: [
                "SinchPushSDKNotificationExtension",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            resources: [
                // The in-app message assets and strings. The in-app sources live in `InApp/` too.
                .process("InApp/Resources")
            ]
        ),
        .testTarget(
            name: "SinchPushSDKTests",
            dependencies: ["SinchPushSDK", "SinchPushSDKNotificationExtension"],
            path: "Tests/SinchPushSDKTests",
            resources: [
                // Relay wire fixtures.
                .copy("PushSocket/Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
